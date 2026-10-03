GHC      ?= ghc
BUILDDIR ?= build
SOURCES  := $(shell find src app -name '*.hs')
# Exactly the build-depends of hclean.cabal; environment files are ignored.
PACKAGES := base directory filepath time unix
GHCFLAGS := -package-env - -hide-all-packages $(addprefix -package ,$(PACKAGES))

.PHONY: all build test clean install

all: hclean

hclean: $(SOURCES)
	$(GHC) $(GHCFLAGS) -isrc -iapp -outputdir $(BUILDDIR) -O2 -Wall -o $@ app/Main.hs

# Cabal build, for development
build:
	cabal build

test:
	cabal test

install: hclean
	install -Dm755 hclean $(DESTDIR)/usr/local/bin/hclean

clean:
	rm -rf hclean $(BUILDDIR)
