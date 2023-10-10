# load targets config
-include Makefile.distros

# load variables and makefile config
-include Makefile.config

#------------------------------------------------------------------------------
# All, alliases
#------------------------------------------------------------------------------
all: $(patsubst %, all-%, $(DISTROS))
	@:

# allow individual distribution targets (e.g., "make debian11")
$(DISTROS): %: all-% ;

# pattern rule for dependencies
all-%: download-% installer-% customize-%
	@${INFO} "All done for ${*}"

#------------------------------------------------------------------------------
# Download
#  - download to build/01_base/$DISTRO
#  - no file suffix, could be iso, qcow2 whatever
#  - TODO: add chesksum verfication somehow
#------------------------------------------------------------------------------
download: $(patsubst %, download-%, $(DISTROS))

download-%: ${DIR_BASE}/%.img
	@${INFO} "Download ${*} done"

${DIR_BASE}/%.img: validate-%
	@${INFO} "Starting $* download"
	curl -sS -L -f -o "$@" "${URL_${*}}"

#------------------------------------------------------------------------------
# Install (optional)
# - run distro installer if cloud/virt image is not available
# - execute packer/$DISTRO/run.sh which runs packet
# - or packer/skip.sh to only create target symlink to base image
#------------------------------------------------------------------------------
installer: $(patsubst %, installer-%, $(DISTROS))

installer-%: ${DIR_INSTALL}/%.qcow2
	@${INFO} "Installer ${*} done"

${DIR_INSTALL}/%.qcow2: ${DIR_BASE}/%.img
	@${INFO} "Starting ${*} installer"
	@if [ -f "packer/${*}/run.sh" ]; then \
		packer/${*}/run.sh ${*} ${@}; \
	else \
		packer/skip.sh ${*}; \
	fi

#------------------------------------------------------------------------------
# Customize
# - execute customize/$DISTRO/run.sh which:
#   - run guestfish customzation scripts
#   - TODO: sysprep
#   - TODO: sparsify
#   - export final image
#------------------------------------------------------------------------------
customize: $(patsubst %, customize-%, $(DISTROS))

customize-%: context-linux ${DIR_EXPORT}/%-${VERSION}-${RELEASE}.qcow2
	@${INFO} "Customize $* done"

${DIR_EXPORT}/%-${VERSION}-${RELEASE}.qcow2: ${DIR_INSTALL}/%.qcow2
	@${INFO} "Starting $* customization"
	@guestfish/run.sh ${*} ${@}

#------------------------------------------------------------------------------
# clean
#------------------------------------------------------------------------------
clean:
	-rm -rf ${DIR_BASE}/*
	-rm -rf ${DIR_INSTALL}/*
	-rm -rf ${DIR_EXPORT}/*

#------------------------------------------------------------------------------
# context-linux
#------------------------------------------------------------------------------
context-linux: $(patsubst %, context-linux/out/%, $(LINUX_CONTEXT_PACKAGES))
	@${INFO} "Generate context-linux done"

context-linux/out/%:
	cd context-linux; ./generate-all.sh

#------------------------------------------------------------------------------
# validate before download
#------------------------------------------------------------------------------
validate-%:
	@if [[ ! "$(DISTROS)" == *"${*}"* ]]; then \
		echo "[ERROR] Unknown distro ${*}"; \
		exit 1; \
	fi

#------------------------------------------------------------------------------
# help
#------------------------------------------------------------------------------
help:
	@echo 'Available distros:'
	@echo '  $(DISTROS)'
	@echo
	@echo 'Usage examples:'
	@echo '  make                    -- build all distros'
	@echo '  make download           -- download all base images'
	@echo '  make installer          -- run installer (unnecessary for some)'
	@echo '  make customize          -- run customization (install context etc)'
	@echo
	@echo '  make <distro>           -- build just one distro'
	@echo '  make download-<distro>  -- download just one'
	@echo '  make installer-<distro> -- download just one'
	@echo '  make customize-<distro> -- download just one'
	@echo '  make context-linux      -- build context linux packages'

