# load variables and makefile config
include Makefile.config

# load possible overrides or non-free definitions
-include Makefile.local

# all, aliases
all: $(patsubst %, packer-%, $(DISTROS)) $(patsubst %, packer-%, $(SERVICES))
distros: $(patsubst %, packer-%, $(DISTROS))
services: $(patsubst %, packer-%, $(SERVICES))

# allow individual distribution targets (e.g., "make debian11")
$(DISTROS) $(SERVICES):  %: packer-% ;

# aliases + dependency
packer-%: context-linux ${DIR_EXPORT}/%.qcow2
	@${INFO} "Packer ${*} done"

packer-service_wordpress: packer-alma8 ${DIR_EXPORT}/service_wordpress.qcow2
	@${INFO} "Packer service_wordpress done"

packer-service_OneKE: packer-ubuntu2204 ${DIR_EXPORT}/service_OneKE.qcow2
	@${INFO} "Packer service_OneKE done"

# run packer build for given distro or service
${DIR_EXPORT}/%.qcow2:
	$(eval DISTRO_NAME := $(shell echo ${*} | sed 's/[0-9].*//'))
	$(eval DISTRO_VER  := $(shell echo ${*} | sed 's/[a-z_]*//'))
	packer/build.sh "${DISTRO_NAME}" "${DISTRO_VER}" ${@}

# context packages
context-linux: $(patsubst %, context-linux/out/%, $(LINUX_CONTEXT_PACKAGES))
	@${INFO} "Generate context-linux done"

context-linux/out/%:
	cd context-linux; ./generate-all.sh

context-windows: $(patsubst %, context-windows/out/%, $(WINDOWS_CONTEXT_PACKAGES))
	@${INFO} "Generate context-windows done"

context-windows/out/%:
	cd context-windows; ./generate-all.sh

clean:
	-rm -rf ${DIR_EXPORT}/*

help:
	@echo 'Usage examples:'
	@echo '    make <distro>          -- build just one distro'
	@echo '    make <service>         -- build just one service'
	@echo
	@echo '    make all               -- build all distros and services'
	@echo '    make distros           -- build all distros'
	@echo '    make services          -- build all services'
	@echo
	@echo '    make context-linux     -- build context linux packages'
	@echo '    make context-windows   -- build windows linux packages'
	@echo
	@echo 'Available distros:'
	@echo "$(shell echo "${DISTROS}" | fmt -w 65 | tr '\n' '\1' )" \
		           | tr '\1' '\n' | sed 's/^/    /'
	@echo 'Available services:'
	@echo '    $(SERVICES)'
	@echo

version:
	@echo $(VERSION)-$(RELEASE) > version
