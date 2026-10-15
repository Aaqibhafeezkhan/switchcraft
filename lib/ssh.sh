#!/usr/bin/env bash
# shellcheck shell=bash
# ssh.sh — one ed25519 key per profile, generated locally, never versioned.

# sc_ssh_ensure_key <profile> <email>
# Returns 0 if the key exists or was created, 1 if it could not be created.
sc_ssh_ensure_key() {
	local p="$1" email="$2" key
	key="$(sc_profile_key "$p")"

	if [[ -f "$key" ]]; then
		ok "key already exists: $key"
		return 0
	fi
	has_cmd ssh-keygen || {
		warn "ssh-keygen not found — install openssh-client, then: switchcraft apply"
		return 1
	}

	sc_mkdir "$HOME/.ssh"
	is_dry || chmod 700 "$HOME/.ssh"

	if is_dry; then
		dry "ssh-keygen -t ed25519 -C $email -f $key"
		return 0
	fi

	if [[ "${SC_ASK_PASSPHRASE:-0}" == 1 ]]; then
		ssh-keygen -t ed25519 -C "$email" -f "$key" || return 1
	else
		ssh-keygen -t ed25519 -C "$email" -f "$key" -N '' -q || return 1
	fi
	chmod 600 "$key"
	chmod 644 "$key.pub"
	ok "key created: $key"
	return 0
}

# sc_ssh_print_pub <profile> — the key the user must register on GitHub.
sc_ssh_print_pub() {
	local key
	key="$(sc_profile_key "$1").pub"
	[[ -f "$key" ]] || return 0
	printf '%s\n' "$(cat "$key")"
}

# sc_ssh_test <profile> — asks GitHub who this key belongs to.
# Prints the GitHub login, or nothing when the key is not registered.
sc_ssh_test() {
	local key out
	key="$(sc_profile_key "$1")"
	[[ -f "$key" ]] || return 1
	has_cmd ssh || return 1
	# GitHub always exits 1 on this probe; the greeting is on stderr.
	out="$(ssh -i "$key" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new \
		-o ConnectTimeout=10 -o BatchMode=yes -T git@github.com 2>&1 || true)"
	[[ "$out" =~ Hi\ ([A-Za-z0-9._-]+) ]] || return 1
	printf '%s\n' "${BASH_REMATCH[1]}"
}
