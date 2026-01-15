.PHONY: install uninstall

PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin

install:
	@mkdir -p $(BINDIR)
	@cp ralph-install.sh $(BINDIR)/ralph-install.sh
	@chmod +x $(BINDIR)/ralph-install.sh
	@echo "Installed ralph-install.sh to $(BINDIR)"
	@echo "Make sure $(BINDIR) is in your PATH"

uninstall:
	@rm -f $(BINDIR)/ralph-install.sh
	@echo "Removed ralph-install.sh from $(BINDIR)"
