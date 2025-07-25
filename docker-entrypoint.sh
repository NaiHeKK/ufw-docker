#!/bin/bash
set -euo pipefail
[[ "${DEBUG:-}" = true ]] && set -x
[[ 0 -eq "$#" ]] && set -- start

ufw_docker_agent=ufw-docker-agent
ufw_docker_agent_image="${ufw_docker_agent_image:-chaifeng/${ufw_docker_agent}:181003}"

function ufw-allow-or-deny-service() {
    declare id="$1"
    declare port="$2"

    if [[ "$port" = deny || "$port" = */deny ]]; then
        port="${port%deny}"
        port="${port%/}"
        declare -a opts=("$id")
        [[ -z "$port" ]] || opts+=("$port")
        run-ufw-docker delete allow "${opts[@]}"
    else
        run-ufw-docker add-service-rule "$id" "$port"
    fi
}

function update-ufw-rules() {
    declare -p | sed -e '/^declare -x ufw_public_/!d' \
                     -e 's/^declare -x ufw_public_//' \
                     -e 's/="/ /' \
                     -e 's/"$//' |
        while read -r id ruleset; do
            declare -a rules=( $(tr ',' '\n' <<< "$ruleset") )
            for rule in "${rules[@]}"; do
                [[ "$rule" = */deny ]] && ufw-allow-or-deny-service "${id}" "${rule#*/}"
            done
            for rule in "${rules[@]}"; do
                [[ "$rule" = */deny ]] || ufw-allow-or-deny-service "${id}" "${rule#*/}"
            done
        done
}

function run-ufw-docker() {
    declare -a docker_opts=(run --rm -t --name "ufw-docker-agent-${RANDOM}-$(date '+%Y%m%d%H%M%S')"
         --cap-add NET_ADMIN --network host
         --env "DEBUG=${DEBUG}"
         -v /var/run/docker.sock:/var/run/docker.sock
         -v /etc/ufw:/etc/ufw "${ufw_docker_agent_image}" "$@")
    docker "${docker_opts[@]}"
}

function get-service-name-of() {
    docker inspect "$1" --format '{{range $k,$v:=.Config.Labels}}{{ if eq $k "com.docker.swarm.service.name" }}{{$v}}{{end}}{{end}}' | grep -E "^.+\$"
}

function get-service-id-of() {
    docker inspect "$1" --format '{{range $k,$v:=.Config.Labels}}{{ if eq $k "com.docker.swarm.service.id" }}{{$v}}{{end}}{{end}}' | grep -E "^.+\$"
}

function main() {
    case "$1" in
        start)
            update-ufw-rules
            while true; do
                sleep "$(( 3600 * 24 * 7 ))" || break
            done
            ;;
        delete|allow|add-service-rule)
            ufw-docker "$@"
            ;;
        update-ufw-rules)
            update-ufw-rules
            ;;
        *)
            if [[ -f "$1" ]]; then
                exec "$@"
            else
                echo "Unknown parameters:" "$@" >&2
                exit 1
            fi
    esac
}

main "$@"
