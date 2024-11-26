// Copyright 2018-present the CoreDHCP Authors. All rights reserved
// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

// Original code: https://github.com/coredhcp/coredhcp/tree/576af8676ffaff9c85800fae235f614cb65410bd/plugins/range
// Adapted by OpenNebula Systems for the VRouter appliance
// Copyright 2024-present OpenNebula Systems

package onerange

import (
	"database/sql"
	"encoding/binary"
	"errors"
	"fmt"
	"net"
	"strings"
	"sync"
	"time"

	"github.com/coredhcp/coredhcp/handler"
	"github.com/coredhcp/coredhcp/logger"
	"github.com/coredhcp/coredhcp/plugins"
	"github.com/coredhcp/coredhcp/plugins/allocators"
	"github.com/coredhcp/coredhcp/plugins/allocators/bitmap"
	"github.com/insomniacslk/dhcp/dhcpv4"
)

var log = logger.GetLogger("plugins/onerange")

// Plugin wraps plugin registration information
var Plugin = plugins.Plugin{
	Name:   "onerange",
	Setup4: setupRange,
}

// Record holds an IP lease record
type Record struct {
	IP       net.IP
	expires  int
	hostname string
}

// PluginState is the data held by an instance of the range plugin
type PluginState struct {
	// Rough lock for the whole plugin, we'll get better performance once we use leasestorage
	sync.Mutex
	// Recordsv4 holds a MAC -> IP address and lease time mapping
	Recordsv4   map[string]*Record
	LeaseTime   time.Duration
	excludedIPs []net.IP
	leasedb     *sql.DB
	allocator   allocators.Allocator
}

// Handler4 handles DHCPv4 packets for the range plugin
func (p *PluginState) Handler4(req, resp *dhcpv4.DHCPv4) (*dhcpv4.DHCPv4, bool) {
	p.Lock()
	defer p.Unlock()
	record, ok := p.Recordsv4[req.ClientHWAddr.String()]
	hostname := req.HostName()
	if !ok {
		// Allocating new address since there isn't one allocated
		log.Printf("MAC address %s is new, leasing new IPv4 address", req.ClientHWAddr.String())
		ip, err := p.allocator.Allocate(net.IPNet{})
		if err != nil {
			log.Errorf("Could not allocate IP for MAC %s: %v", req.ClientHWAddr.String(), err)
			return nil, true
		}
		rec := Record{
			IP:       ip.IP.To4(),
			expires:  int(time.Now().Add(p.LeaseTime).Unix()),
			hostname: hostname,
		}
		err = p.saveIPAddress(req.ClientHWAddr, &rec)
		if err != nil {
			log.Errorf("SaveIPAddress for MAC %s failed: %v", req.ClientHWAddr.String(), err)
		}
		p.Recordsv4[req.ClientHWAddr.String()] = &rec
		record = &rec
	} else {
		// Ensure we extend the existing lease at least past when the one we're giving expires
		expiry := time.Unix(int64(record.expires), 0)
		if expiry.Before(time.Now().Add(p.LeaseTime)) {
			record.expires = int(time.Now().Add(p.LeaseTime).Round(time.Second).Unix())
			record.hostname = hostname
			err := p.saveIPAddress(req.ClientHWAddr, record)
			if err != nil {
				log.Errorf("Could not persist lease for MAC %s: %v", req.ClientHWAddr.String(), err)
			}
		}
	}
	resp.YourIPAddr = record.IP
	resp.Options.Update(dhcpv4.OptIPAddressLeaseTime(p.LeaseTime.Round(time.Second)))
	log.Printf("found IP address %s for MAC %s", record.IP, req.ClientHWAddr.String())
	return resp, false
}

func setupRange(args ...string) (handler.Handler4, error) {
	var (
		err error
		p   PluginState
	)

	if len(args) < 4 {
		return nil, fmt.Errorf("invalid number of arguments, want: 4 (file name, start IP, end IP, lease time), got: %d", len(args))
	}
	filename := args[0]
	if filename == "" {
		return nil, errors.New("file name cannot be empty")
	}
	ipRangeStart := net.ParseIP(args[1])
	if ipRangeStart.To4() == nil {
		return nil, fmt.Errorf("invalid IPv4 address: %v", args[1])
	}
	ipRangeEnd := net.ParseIP(args[2])
	if ipRangeEnd.To4() == nil {
		return nil, fmt.Errorf("invalid IPv4 address: %v", args[2])
	}
	if binary.BigEndian.Uint32(ipRangeStart.To4()) >= binary.BigEndian.Uint32(ipRangeEnd.To4()) {
		return nil, errors.New("start of IP range has to be lower than the end of an IP range")
	}

	p.allocator, err = bitmap.NewIPv4Allocator(ipRangeStart, ipRangeEnd)
	if err != nil {
		return nil, fmt.Errorf("could not create an allocator: %w", err)
	}

	p.LeaseTime, err = time.ParseDuration(args[3])
	if err != nil {
		return nil, fmt.Errorf("invalid lease duration: %v", args[3])
	}

	// parse a list of excluded IPs as fifth argument
	if len(args) > 4 {
		excludedIPs := args[4]
		for _, ip := range strings.Split(excludedIPs, ",") {
			excluded := net.ParseIP(strings.TrimSpace(ip))
			if excluded.To4() == nil {
				return nil, fmt.Errorf("invalid excluded IP address: %v", ip)
			}
			p.excludedIPs = append(p.excludedIPs, excluded)
		}
	}

	// check that the excluded IPs belongs to the range and pre-allocate them
	// preallocated IPs will not be stored in the lease database, but they will be kept at the allocator level
	// who is the responsible of managing the IP availability
	for _, excluded := range p.excludedIPs {
		if binary.BigEndian.Uint32(excluded.To4()) < binary.BigEndian.Uint32(ipRangeStart.To4()) ||
			binary.BigEndian.Uint32(excluded.To4()) > binary.BigEndian.Uint32(ipRangeEnd.To4()) {
			return nil, fmt.Errorf("excluded IP %v is not in the range %v-%v", excluded, ipRangeStart, ipRangeEnd)
		}
		if _, err := p.allocator.Allocate(net.IPNet{IP: excluded}); err != nil {
			return nil, fmt.Errorf("could not pre-allocate excluded IP %v: %w", excluded, err)
		}
	}

	if err := p.registerBackingDB(filename); err != nil {
		return nil, fmt.Errorf("could not setup lease storage: %w", err)
	}
	p.Recordsv4, err = loadRecords(p.leasedb)
	if err != nil {
		return nil, fmt.Errorf("could not load records from file: %v", err)
	}

	log.Printf("Loaded %d DHCPv4 leases from %s", len(p.Recordsv4), filename)

	for _, v := range p.Recordsv4 {
		ip, err := p.allocator.Allocate(net.IPNet{IP: v.IP})
		if err != nil {
			return nil, fmt.Errorf("failed to re-allocate leased ip %v: %v", v.IP.String(), err)
		}
		if ip.IP.String() != v.IP.String() {
			return nil, fmt.Errorf("allocator did not re-allocate requested leased ip %v: %v", v.IP.String(), ip.String())
		}
	}

	return p.Handler4, nil
}
