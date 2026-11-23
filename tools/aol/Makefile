# SPDX-FileCopyrightText: 2026 Cat-Ling
# SPDX-License-Identifier: GPL-3.0-or-later

PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
MANDIR ?= $(PREFIX)/share/man
INSTALL ?= install
GO ?= go

.PHONY: all build test vet lint check install uninstall clean

all: build

build:
	CGO_ENABLED=0 $(GO) build -trimpath -o madeira-aol ./cmd/madeira-aol

test:
	$(GO) test -race ./...

vet:
	CGO_ENABLED=0 $(GO) vet ./...

lint:
	test -z "$$(gofmt -l .)"

check: lint vet test

install: build
	$(INSTALL) -d "$(DESTDIR)$(BINDIR)" "$(DESTDIR)$(MANDIR)/man1"
	$(INSTALL) -m 0755 madeira-aol "$(DESTDIR)$(BINDIR)/madeira-aol"
	$(INSTALL) -m 0644 doc/madeira-aol.1 "$(DESTDIR)$(MANDIR)/man1/madeira-aol.1"

uninstall:
	rm -f "$(DESTDIR)$(BINDIR)/madeira-aol" "$(DESTDIR)$(MANDIR)/man1/madeira-aol.1"

clean:
	rm -f madeira-aol
