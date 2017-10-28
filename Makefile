.PHONY: all
all:
	jbuilder build src/trackerscraper.exe @install

.PHONY: install
install:
	jbuilder install

.PHONY: uninstall
uninstall:
	jbuilder uninstall

.PHONY: clean
clean: #adapted from github.com/diml/lambda-term
	rm -rf _build trackerscraper.install
	find . -name .merlin -delete