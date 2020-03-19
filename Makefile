# See LICENSE for licensing information.

PROJECT = gun
PROJECT_DESCRIPTION = HTTP/1.1, HTTP/2 and Websocket client for Erlang/OTP.
PROJECT_VERSION = 2.0.0-pre.1

# Options.

# ERLC_OPTS = -DDEBUG_PROXY=1
CT_OPTS += -ct_hooks gun_ct_hook [] # -boot start_sasl

# Dependencies.

LOCAL_DEPS = ssl

DEPS = cowlib
dep_cowlib = git https://github.com/ninenines/cowlib rfc6265bis

DOC_DEPS = asciideck

TEST_DEPS = $(if $(CI_ERLANG_MK),ci.erlang.mk) ct_helper cowboy
dep_ct_helper = git https://github.com/extend/ct_helper.git master
dep_cowboy_commit = master

# CI configuration.

dep_ci.erlang.mk = git https://github.com/ninenines/ci.erlang.mk master
DEP_EARLY_PLUGINS = ci.erlang.mk

AUTO_CI_OTP ?= OTP-20+
AUTO_CI_HIPE ?= OTP-LATEST
# AUTO_CI_ERLLVM ?= OTP-LATEST
AUTO_CI_WINDOWS ?= OTP-20+

# Standard targets.

include erlang.mk

# Don't run the autobahn test suite by default.

ifndef FULL
CT_SUITES := $(filter-out ws_autobahn,$(CT_SUITES))
endif

# Enable eunit.

TEST_ERLC_OPTS += +'{parse_transform, eunit_autoexport}'

# Generate rebar.config on build.

app:: rebar.config

# h2specd setup.

GOPATH := $(ERLANG_MK_TMP)/gopath
export GOPATH

H2SPECD := $(GOPATH)/src/github.com/summerwind/h2spec/h2specd
export H2SPECD

# @todo It would be better to allow these dependencies to be specified
# on a per-target basis instead of for all targets.
test-build:: $(H2SPECD)

$(H2SPECD):
	$(gen_verbose) mkdir -p $(GOPATH)/src/github.com/summerwind
	-$(verbose) git clone --depth 1 https://github.com/summerwind/h2spec $(dir $(H2SPECD))
	-$(verbose) $(MAKE) -C $(dir $(H2SPECD)) build MAKEFLAGS=
	-$(verbose) go build -o $(H2SPECD) $(dir $(H2SPECD))/cmd/h2spec/h2specd.go

# Public suffix module generator.
# https://publicsuffix.org/list/

GEN_URL = https://publicsuffix.org/list/public_suffix_list.dat
GEN_DAT = $(ERLANG_MK_TMP)/public_suffix_list.dat
GEN_SRC = src/gun_public_suffix.erl.src
GEN_OUT = src/gun_public_suffix.erl

# We use idna for punycode encoding when generating the module.
dep_idna = git https://github.com/benoitc/erlang-idna 6.0.0
$(eval $(call dep_target,idna))

# 33 is $!
define gen.erl
	{ok, Dat} = file:read_file("$(GEN_DAT)"),
	Lines = [L || L <- string:split(Dat, <<"\n">>, all),
		L =/= <<>>, binary:first(L) =/= $$/, binary:first(L) =/= $$\s],
	Punycode = fun(V) ->
		unicode:characters_to_binary(idna:encode(unicode:characters_to_list(V)))
	end,
	M0 = [string:replace(L, <<"*">>, <<"star-gen-placeholder">>, all)
		|| L <- Lines, binary:first(L) =/= 33],
	M1 = [io_lib:format("m(S = ~p) -> e(S);~n", [string:split(Punycode(L), <<".">>, all)])
		|| L <- M0],
	M = string:replace(M1, <<"<<\\"star-gen-placeholder\\">>">>, <<"_">>, all),
	E = [io_lib:format("e(~p) -> false;~n", [string:split(Punycode(L), <<".">>, all)])
		|| <<"!",L/bits>> <- Lines],
	{ok, Src0} = file:read_file("$(GEN_SRC)"),
	Src1 = string:replace(Src0, <<"%% GENERATED_M\n">>, M),
	Src = string:replace(Src1, <<"%% GENERATED_E\n">>, E),
	ok = file:write_file("$(GEN_OUT)", Src),
	halt().
endef

.PHONY: gen gen-idna

gen-idna: $(DEPS_DIR)/idna
	$(verbose) $(MAKE) -C $?

gen: gen-idna | $(ERLANG_MK_TMP)
	$(gen_verbose) wget -qO - $(GEN_URL) > $(GEN_DAT)
	$(gen_verbose) $(call erlang,$(call gen.erl))

# Prepare for the release.

prepare_tag:
	$(verbose) echo -n "Most recent tag:            "
	$(verbose) git tag | tail -n1
	$(verbose) git verify-tag `git tag | tail -n1`
	$(verbose) echo -n "MAKEFILE: "
	$(verbose) grep -m1 PROJECT_VERSION Makefile
	$(verbose) echo -n "APP:                 "
	$(verbose) grep -m1 vsn ebin/$(PROJECT).app | sed 's/	//g'
	$(verbose) echo
	$(verbose) echo "Links in the README:"
	$(verbose) grep http.*:// README.asciidoc
	$(verbose) echo
	$(verbose) echo "Titles in most recent CHANGELOG:"
	$(verbose) for f in `ls -rv doc/src/guide/migrating_from_*.asciidoc | head -n1`; do \
		echo $$f:; \
		grep == $$f; \
	done
