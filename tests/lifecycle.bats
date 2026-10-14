#!/usr/bin/env bats
load test_helper

@test "apply is idempotent" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	add_profile work work@company.com
	cp "$SANDBOX/.gitconfig" "$SANDBOX/first"
	cp "$SANDBOX/projects/work/.envrc" "$SANDBOX/envrc.first"
	sc apply >/dev/null 2>&1
	sc apply >/dev/null 2>&1
	diff -q "$SANDBOX/first" "$SANDBOX/.gitconfig"
	diff -q "$SANDBOX/envrc.first" "$SANDBOX/projects/work/.envrc"
	[ "$(grep -c 'switchcraft >>>' "$SANDBOX/.gitconfig")" -eq 1 ]
}

@test "link binds a directory outside the projects root" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	add_profile work work@company.com
	mkdir -p "$SANDBOX/elsewhere/client"
	run sc link work "$SANDBOX/elsewhere/client"
	[ "$status" -eq 0 ]
	[ -f "$SANDBOX/elsewhere/client/.envrc" ]
	git -C "$SANDBOX/elsewhere/client" init -q
	[ "$(git -C "$SANDBOX/elsewhere/client" config user.email)" = "work@company.com" ]
}

@test "link refuses an unknown profile" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	run sc link nosuch "$SANDBOX/x"
	[ "$status" -ne 0 ]
}

@test "the deepest linked directory wins" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	add_profile outer outer@x.com
	add_profile inner inner@x.com
	mkdir -p "$SANDBOX/tree/sub"
	sc link outer "$SANDBOX/tree" >/dev/null 2>&1
	sc link inner "$SANDBOX/tree/sub" >/dev/null 2>&1
	git -C "$SANDBOX/tree/sub" init -q
	[ "$(git -C "$SANDBOX/tree/sub" config user.email)" = "inner@x.com" ]
}

@test "unlink stops managing a directory but keeps its files" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	add_profile work work@company.com
	echo 'keep me' >"$SANDBOX/projects/work/file.txt"
	run sc unlink "$SANDBOX/projects/work"
	[ "$status" -eq 0 ]
	[ -f "$SANDBOX/projects/work/file.txt" ]
	! gitconfig | grep -q "projects/work/"
}

@test "status reports the profile and warns when unmanaged" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	add_profile work work@company.com
	run sc status "$SANDBOX/projects/work"
	[[ "$output" == *work* ]]
	run sc status "$SANDBOX"
	[[ "$output" == *unmanaged* ]]
}

@test "remove drops the profile and its includeIf" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	add_profile work work@company.com
	add_profile personal me@gmail.com
	run sc remove work
	[ "$status" -eq 0 ]
	! gitconfig | grep -q 'git-profiles/work'
	gitconfig | grep -q 'git-profiles/personal'
	[ ! -f "$SANDBOX/.config/git-profiles/work" ]
	# the key is kept unless --purge
	[ -f "$SANDBOX/.ssh/id_ed25519_work" ]
}

@test "remove --purge deletes the key and config dirs" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	add_profile work work@company.com
	run sc remove work --purge
	[ "$status" -eq 0 ]
	[ ! -e "$SANDBOX/.ssh/id_ed25519_work" ]
	[ ! -e "$SANDBOX/.claude-work" ]
}

@test "uninstall reverses every block it wrote" {
	printf '[alias]\n\tst = status\n' >"$SANDBOX/.gitconfig"
	printf '# my rc\n' >"$SANDBOX/.bashrc"
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	add_profile work work@company.com
	run sc uninstall
	[ "$status" -eq 0 ]
	! grep -q 'switchcraft' "$SANDBOX/.gitconfig"
	grep -q 'st = status' "$SANDBOX/.gitconfig"
	! grep -q 'direnv hook' "$SANDBOX/.bashrc"
	grep -q '# my rc' "$SANDBOX/.bashrc"
	[ ! -e "$SANDBOX/projects/work/.envrc" ]
	[ ! -f "$SANDBOX/.config/git-profiles/work" ]
	# keys and history are kept without --purge
	[ -f "$SANDBOX/.ssh/id_ed25519_work" ]
	[ -f "$SANDBOX/.config/switchcraft/config" ]
}

@test "uninstall --purge removes keys and the config" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	add_profile work work@company.com
	run sc uninstall --purge
	[ "$status" -eq 0 ]
	[ ! -e "$SANDBOX/.ssh/id_ed25519_work" ]
	[ ! -e "$SANDBOX/.config/switchcraft/config" ]
}

@test "signing is enabled globally and cleared on uninstall" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	add_profile work work@company.com
	[ "$(git config --global gpg.format)" = "ssh" ]
	[ "$(git config --global commit.gpgsign)" = "true" ]
	[ -f "$SANDBOX/.config/switchcraft/allowed_signers" ]
	grep -q 'namespaces="git"' "$SANDBOX/.config/switchcraft/allowed_signers"
	sc uninstall >/dev/null 2>&1
	[ -z "$(git config --global commit.gpgsign || true)" ]
}
