kern_tools_LIST = kgit kgit-meta \
		  kconf_check \
		  kgit-create-buckets \
		  get_defconfig scc \
		  merge_config.sh spp kgit-s2q \
		  symbol_why.py \
		  kconfig-diff2frag.py

cmds := $(wildcard tools/scc-cmds/*)
libs := Kconfiglib/kconfiglib.py

INSTALL=install
RM=rm
ECHO=echo

define echo_action
    if [ "x$1" = "xDone" ]; then \
        $(ECHO) >&2 -e "=======================================================\
                    \n$1: $2 \
                    \n======================================================="; \
    else \
        $(ECHO) >&2 -e "-------------------------------------------------------\
                   \n$1: $2 \
                   \n-------------------------------------------------------"; \
    fi
endef
define install_cmd
	$(INSTALL) -m 0755 $(1) $(DESTDIR)/scc-cmds/;
endef
define install_lib
	$(INSTALL) -m 0755 $(1) $(DESTDIR);
endef
define install_tool
	$(INSTALL) -m 0755 tools/$(1) $(DESTDIR);
endef
define remove_tool
	$(RM) -f $(DESTDIR)/$(1);
endef

all:
	@$(ECHO) No action provided, so nothing will be done
	@$(ECHO) Available actions are 'install' and 'clean'

install:
	@if [ -z "$(DESTDIR)" ]; then \
		$(ECHO) "Error. DESTDIR must be provided"; \
		exit 1; \
	fi;
	@$(call echo_action,Install,kern_tools)
	@$(INSTALL) -d $(DESTDIR)
	@$(foreach tool,$(kern_tools_LIST),$(call install_tool,$(tool)))
	@$(INSTALL) -d $(DESTDIR)/scc-cmds/
	@$(foreach cmd,$(cmds),$(call install_cmd,$(cmd)))
	@$(foreach lib,$(libs),$(call install_lib,$(lib)))
	@$(MAKE_STAMP)

clean:
	@if [ -z "$(DESTDIR)" ]; then \
		$(ECHO) "Error. DESTDIR must be provided"; \
		exit 1; \
	fi;
	@$(call echo_action,Clean,kern_tools)
	@$(foreach tool,$(kern_tools_LIST),$(call remove_tool,$(tool)))
	@-$(RM) -f $(addprefix $(STAMP_DIR)/kern_tools,$(PKG_CLEAN_SUFFIXES));
