PROJECT = rabbitmq_server_release
VERSION ?= 0.0.0

# Release artifacts are put in $(PACKAGES_DIR).
PACKAGES_DIR ?= $(abspath PACKAGES)

DEPS = rabbit_common rabbit $(PLUGINS)

# List of plugins to include in a RabbitMQ release.
PLUGINS := rabbitmq_amqp1_0 \
	   rabbitmq_auth_backend_ldap \
	   rabbitmq_auth_mechanism_ssl \
	   rabbitmq_consistent_hash_exchange \
	   rabbitmq_event_exchange \
	   rabbitmq_federation \
	   rabbitmq_federation_management \
	   rabbitmq_jms_topic_exchange \
	   rabbitmq_management \
	   rabbitmq_management_agent \
	   rabbitmq_management_visualiser \
	   rabbitmq_mqtt \
	   rabbitmq_recent_history_exchange \
	   rabbitmq_sharding \
	   rabbitmq_shovel \
	   rabbitmq_shovel_management \
	   rabbitmq_stomp \
	   rabbitmq_top \
	   rabbitmq_tracing \
	   rabbitmq_trust_store \
	   rabbitmq_web_dispatch \
	   rabbitmq_web_stomp \
	   rabbitmq_web_stomp_examples

DEP_PLUGINS = rabbit_common/mk/rabbitmq-run.mk \
	      rabbit_common/mk/rabbitmq-dist.mk \
	      rabbit_common/mk/rabbitmq-tools.mk

# FIXME: Use erlang.mk patched for RabbitMQ, while waiting for PRs to be
# reviewed and merged.

ERLANG_MK_REPO = https://github.com/rabbitmq/erlang.mk.git
ERLANG_MK_COMMIT = rabbitmq-tmp

include rabbitmq-components.mk
include erlang.mk

# --------------------------------------------------------------------
# Distribution.
# --------------------------------------------------------------------

.PHONY: source-dist clean-source-dist

SOURCE_DIST_BASE ?= rabbitmq-server
SOURCE_DIST_SUFFIXES ?= tar.xz zip
SOURCE_DIST ?= $(PACKAGES_DIR)/$(SOURCE_DIST_BASE)-$(VERSION)

# The first source distribution file is used by packages: if the archive
# type changes, you must update all packages' Makefile.
SOURCE_DIST_FILES = $(addprefix $(SOURCE_DIST).,$(SOURCE_DIST_SUFFIXES))

.PHONY: $(SOURCE_DIST_FILES)

source-dist: $(SOURCE_DIST_FILES)
	@:

RSYNC ?= rsync
RSYNC_V_0 =
RSYNC_V_1 = -v
RSYNC_V_2 = -v
RSYNC_V = $(RSYNC_V_$(V))
RSYNC_FLAGS += -a $(RSYNC_V)		\
	       --exclude '.sw?' --exclude '.*.sw?'	\
	       --exclude '*.beam'			\
	       --exclude '*.d'				\
	       --exclude '*.pyc'			\
	       --exclude '.git*'			\
	       --exclude '.hg*'				\
	       --exclude '.travis.yml'			\
	       --exclude '.*.plt'			\
	       --exclude '$(notdir $(ERLANG_MK_TMP))'	\
	       --exclude 'ebin'				\
	       --exclude 'packaging'			\
	       --exclude 'erl_crash.dump'		\
	       --exclude 'MnesiaCore.*'			\
	       --exclude 'cover/'			\
	       --exclude 'deps/'			\
	       --exclude 'ebin/'			\
	       --exclude '$(notdir $(DEPS_DIR))/'	\
	       --exclude 'logs/'			\
	       --exclude 'plugins/'			\
	       --exclude '$(notdir $(DIST_DIR))/'	\
	       --exclude 'test'				\
	       --exclude 'xrefr'			\
	       --exclude '/$(notdir $(PACKAGES_DIR))/'	\
	       --exclude '/PACKAGES/'			\
	       --exclude '/cowboy/doc/'			\
	       --exclude '/cowboy/examples/'		\
	       --exclude '/rabbitmq_amqp1_0/test/swiftmq/build/'\
	       --exclude '/rabbitmq_amqp1_0/test/swiftmq/swiftmq*'\
	       --exclude '/rabbitmq_mqtt/test/build/'	\
	       --exclude '/rabbitmq_mqtt/test/test_client/'\
	       --delete					\
	       --delete-excluded

TAR ?= tar
TAR_V_0 =
TAR_V_1 = -v
TAR_V_2 = -v
TAR_V = $(TAR_V_$(V))

GZIP ?= gzip
BZIP2 ?= bzip2
XZ ?= xz

ZIP ?= zip
ZIP_V_0 = -q
ZIP_V_1 =
ZIP_V_2 =
ZIP_V = $(ZIP_V_$(V))

.PHONY: $(SOURCE_DIST)
.PHONY: clean-source-dist distclean-packages

$(SOURCE_DIST): $(ERLANG_MK_RECURSIVE_DEPS_LIST)
	$(verbose) mkdir -p $(dir $@)
	$(gen_verbose) $(RSYNC) $(RSYNC_FLAGS) ./ $@/
	$(verbose) echo "$(PROJECT) $$(git rev-parse HEAD) $$(git describe --tags --exact-match 2>/dev/null || git symbolic-ref -q --short HEAD)" > $@/git-revisions.txt
	$(verbose) cat packaging/common/LICENSE.head > $@/LICENSE
	$(verbose) mkdir -p $@/deps/licensing
	$(verbose) for dep in $$(cat $(ERLANG_MK_RECURSIVE_DEPS_LIST) | LC_COLLATE=C sort); do \
		$(RSYNC) $(RSYNC_FLAGS) \
		 $$dep \
		 $@/deps; \
		if test -f $@/deps/$$(basename $$dep)/erlang.mk && \
		   test "$$(wc -l $@/deps/$$(basename $$dep)/erlang.mk | awk '{print $$1;}')" = "1" && \
		   grep -qs -E "^[[:blank:]]*include[[:blank:]]+(erlang\.mk|.*/erlang\.mk)$$" $@/deps/$$(basename $$dep)/erlang.mk; then \
			echo "include ../../erlang.mk" > $@/deps/$$(basename $$dep)/erlang.mk; \
		fi; \
		sed -E -i.bak "s|^[[:blank:]]*include[[:blank:]]+\.\./.*erlang.mk$$|include ../../erlang.mk|" \
		 $@/deps/$$(basename $$dep)/Makefile && \
		rm $@/deps/$$(basename $$dep)/Makefile.bak; \
		if test -f "$$dep/license_info"; then \
			cp "$$dep/license_info" "$@/deps/licensing/license_info_$$(basename "$$dep")"; \
			cat "$$dep/license_info" >> $@/LICENSE; \
		fi; \
		find "$$dep" -maxdepth 1 -name 'LICENSE-*' -exec cp '{}' $@/deps/licensing \; ; \
		(cd $$dep; echo "$$(basename "$$dep") $$(git rev-parse HEAD) $$(git describe --tags --exact-match 2>/dev/null || git symbolic-ref -q --short HEAD)") >> $@/git-revisions.txt; \
	done
	$(verbose) cat packaging/common/LICENSE.tail >> $@/LICENSE
	$(verbose) find $@/deps/licensing -name 'LICENSE-*' -exec cp '{}' $@ \;
	$(verbose) for file in $$(find $@ -name '*.app.src'); do \
		sed -E -i.bak \
		  -e 's/[{]vsn[[:blank:]]*,[[:blank:]]*(""|"0.0.0")[[:blank:]]*}/{vsn, "$(VERSION)"}/' \
		  -e 's/[{]broker_version_requirements[[:blank:]]*,[[:blank:]]*\[\][[:blank:]]*}/{broker_version_requirements, ["$(VERSION)"]}/' \
		  $$file; \
		rm $$file.bak; \
	done

# TODO: Fix file timestamps to have reproducible source archives.
# $(verbose) find $@ -not -name 'git-revisions.txt' -print0 | xargs -0 touch -r $@/git-revisions.txt

$(SOURCE_DIST).tar.gz: $(SOURCE_DIST)
	$(gen_verbose) cd $(dir $(SOURCE_DIST)) && \
		find $(notdir $(SOURCE_DIST)) -print0 | LC_COLLATE=C sort -z | \
		xargs -0 $(TAR) $(TAR_V) --no-recursion -cf - | \
		$(GZIP) --best > $@

$(SOURCE_DIST).tar.bz2: $(SOURCE_DIST)
	$(gen_verbose) cd $(dir $(SOURCE_DIST)) && \
		find $(notdir $(SOURCE_DIST)) -print0 | LC_COLLATE=C sort -z | \
		xargs -0 $(TAR) $(TAR_V) --no-recursion -cf - | \
		$(BZIP2) > $@

$(SOURCE_DIST).tar.xz: $(SOURCE_DIST)
	$(gen_verbose) cd $(dir $(SOURCE_DIST)) && \
		find $(notdir $(SOURCE_DIST)) -print0 | LC_COLLATE=C sort -z | \
		xargs -0 $(TAR) $(TAR_V) --no-recursion -cf - | \
		$(XZ) > $@

$(SOURCE_DIST).zip: $(SOURCE_DIST)
	$(verbose) rm -f $@
	$(gen_verbose) cd $(dir $(SOURCE_DIST)) && \
		find $(notdir $(SOURCE_DIST)) -print0 | LC_COLLATE=C sort -z | \
		xargs -0 $(ZIP) $(ZIP_V) $@

clean:: clean-source-dist

clean-source-dist:
	$(gen_verbose) rm -rf -- $(SOURCE_DIST_BASE)-*

distclean:: distclean-packages

distclean-packages:
	$(gen_verbose) rm -rf -- $(PACKAGES_DIR)

# --------------------------------------------------------------------
# Packaging.
# --------------------------------------------------------------------

.PHONY: packages package-deb \
	package-rpm package-rpm-fedora package-rpm-suse \
	package-windows package-standalone-macosx \
	package-generic-unix

# This variable is exported so sub-make instances know where to find the
# archive.
PACKAGES_SOURCE_DIST_FILE ?= $(firstword $(SOURCE_DIST_FILES))

packages package-deb package-rpm package-rpm-fedora \
package-rpm-suse package-windows package-standalone-macosx \
package-generic-unix: $(PACKAGES_SOURCE_DIST_FILE)
	$(verbose) $(MAKE) -C packaging $@ \
		SOURCE_DIST_FILE=$(abspath $(PACKAGES_SOURCE_DIST_FILE))

# --------------------------------------------------------------------
# Installation.
# --------------------------------------------------------------------

.PHONY: manpages web-manpages distclean-manpages

manpages web-manpages distclean-manpages:
	$(MAKE) -C $(DEPS_DIR)/rabbit $@ DEPS_DIR=$(DEPS_DIR)

.PHONY: install install-erlapp install-scripts install-bin install-man \
	install-windows install-windows-erlapp install-windows-scripts \
	install-windows-docs

DESTDIR ?=

PREFIX ?= /usr/local
WINDOWS_PREFIX ?= rabbitmq-server-windows-$(VERSION)

MANDIR ?= $(PREFIX)/share/man
RMQ_ROOTDIR ?= $(PREFIX)/lib/erlang
RMQ_BINDIR ?= $(RMQ_ROOTDIR)/bin
RMQ_LIBDIR ?= $(RMQ_ROOTDIR)/lib
RMQ_ERLAPP_DIR ?= $(RMQ_LIBDIR)/rabbitmq_server-$(VERSION)

SCRIPTS = rabbitmq-defaults \
	  rabbitmq-env \
	  rabbitmq-server \
	  rabbitmqctl \
	  rabbitmq-plugins \
	  cuttlefish

WINDOWS_SCRIPTS = rabbitmq-defaults.bat \
		  rabbitmq-echopid.bat \
		  rabbitmq-env.bat \
		  rabbitmq-plugins.bat \
		  rabbitmq-server.bat \
		  rabbitmq-service.bat \
		  rabbitmqctl.bat \
		  cuttlefish

UNIX_TO_DOS ?= todos

inst_verbose_0 = @echo " INST  " $@;
inst_verbose = $(inst_verbose_$(V))

install: install-erlapp install-scripts

install-erlapp: dist
	$(verbose) mkdir -p $(DESTDIR)$(RMQ_ERLAPP_DIR)
	$(inst_verbose) cp -r \
		LICENSE* \
		$(DEPS_DIR)/rabbit/ebin \
		$(DEPS_DIR)/rabbit/priv \
		$(DEPS_DIR)/rabbit/INSTALL \
		$(DIST_DIR) \
		$(DESTDIR)$(RMQ_ERLAPP_DIR)
	$(verbose) echo "Put your EZs here and use rabbitmq-plugins to enable them." \
		> $(DESTDIR)$(RMQ_ERLAPP_DIR)/$(notdir $(DIST_DIR))/README

	@# FIXME: Why do we copy headers?
	$(verbose) cp -r \
		$(DEPS_DIR)/rabbit/include \
		$(DESTDIR)$(RMQ_ERLAPP_DIR)
	@# rabbitmq-common provides headers too: copy them to
	@# rabbitmq_server/include.
	$(verbose) cp -r \
		$(DEPS_DIR)/rabbit_common/include \
		$(DESTDIR)$(RMQ_ERLAPP_DIR)

install-scripts:
	$(verbose) mkdir -p $(DESTDIR)$(RMQ_ERLAPP_DIR)/sbin
	$(inst_verbose) for script in $(SCRIPTS); do \
		cp "$(DEPS_DIR)/rabbit/scripts/$$script" \
			"$(DESTDIR)$(RMQ_ERLAPP_DIR)/sbin"; \
		chmod 0755 "$(DESTDIR)$(RMQ_ERLAPP_DIR)/sbin/$$script"; \
	done

# FIXME: We do symlinks to scripts in $(RMQ_ERLAPP_DIR))/sbin but this
# code assumes a certain hierarchy to make relative symlinks.
install-bin: install-scripts
	$(verbose) mkdir -p $(DESTDIR)$(RMQ_BINDIR)
	$(inst_verbose) for script in $(SCRIPTS); do \
		test -e $(DESTDIR)$(RMQ_BINDIR)/$$script || \
			ln -sf ../lib/$(notdir $(RMQ_ERLAPP_DIR))/sbin/$$script \
			 $(DESTDIR)$(RMQ_BINDIR)/$$script; \
	done

install-man: manpages
	$(inst_verbose) sections=$$(ls -1 $(DEPS_DIR)/rabbit/docs/*.[1-9] \
		| sed -E 's/.*\.([1-9])$$/\1/' | uniq | sort); \
	for section in $$sections; do \
		mkdir -p $(DESTDIR)$(MANDIR)/man$$section; \
		for manpage in $(DEPS_DIR)/rabbit/docs/*.$$section; do \
			gzip < $$manpage \
			 > $(DESTDIR)$(MANDIR)/man$$section/$$(basename $$manpage).gz; \
		done; \
	done

install-windows: install-windows-erlapp install-windows-scripts install-windows-docs

install-windows-erlapp: dist
	$(verbose) mkdir -p $(DESTDIR)$(WINDOWS_PREFIX)
	$(inst_verbose) cp -r \
		LICENSE* \
		$(DEPS_DIR)/rabbit/ebin \
		$(DEPS_DIR)/rabbit/priv \
		$(DEPS_DIR)/rabbit/INSTALL \
		$(DIST_DIR) \
		$(DESTDIR)$(WINDOWS_PREFIX)
	$(verbose) echo "Put your EZs here and use rabbitmq-plugins.bat to enable them." \
		> $(DESTDIR)$(WINDOWS_PREFIX)/$(notdir $(DIST_DIR))/README.txt
	$(verbose) $(UNIX_TO_DOS) $(DESTDIR)$(WINDOWS_PREFIX)/plugins/README.txt

	@# FIXME: Why do we copy headers?
	$(verbose) cp -r \
		$(DEPS_DIR)/rabbit/include \
		$(DESTDIR)$(WINDOWS_PREFIX)
	@# rabbitmq-common provides headers too: copy them to
	@# rabbitmq_server/include.
	$(verbose) cp -r \
		$(DEPS_DIR)/rabbit_common/include \
		$(DESTDIR)$(WINDOWS_PREFIX)

install-windows-scripts:
	$(verbose) mkdir -p $(DESTDIR)$(WINDOWS_PREFIX)/sbin
	$(inst_verbose) for script in $(WINDOWS_SCRIPTS); do \
		cp "$(DEPS_DIR)/rabbit/scripts/$$script" \
			"$(DESTDIR)$(WINDOWS_PREFIX)/sbin"; \
		chmod 0755 "$(DESTDIR)$(WINDOWS_PREFIX)/sbin/$$script"; \
	done

install-windows-docs: install-windows-erlapp
	$(verbose) mkdir -p $(DESTDIR)$(WINDOWS_PREFIX)/etc
	$(inst_verbose) xmlto -o . xhtml-nochunks \
		$(DEPS_DIR)/rabbit/docs/rabbitmq-service.xml
	$(verbose) elinks -dump -no-references -no-numbering \
		rabbitmq-service.html \
		> $(DESTDIR)$(WINDOWS_PREFIX)/readme-service.txt
	$(verbose) rm rabbitmq-service.html
	$(verbose) cp $(DEPS_DIR)/rabbit/docs/rabbitmq.config.example \
		$(DESTDIR)$(WINDOWS_PREFIX)/etc
	$(verbose) for file in \
	 $(DESTDIR)$(WINDOWS_PREFIX)/readme-service.txt \
	 $(DESTDIR)$(WINDOWS_PREFIX)/LICENSE* \
	 $(DESTDIR)$(WINDOWS_PREFIX)/INSTALL \
	 $(DESTDIR)$(WINDOWS_PREFIX)/etc/rabbitmq.config.example; do \
		$(UNIX_TO_DOS) "$$file"; \
		case "$$file" in \
		*.txt) ;; \
		*.example) ;; \
		*) mv "$$file" "$$file.txt" ;; \
		esac; \
	done
