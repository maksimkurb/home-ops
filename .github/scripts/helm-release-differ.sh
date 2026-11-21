#!/usr/bin/env bash

# shellcheck source=/dev/null
source "$(dirname "${0}")/lib/functions.sh"

set -o errexit
set -o nounset
set -o pipefail
shopt -s lastpipe

show_help() {
cat << EOF
Usage: $(basename "$0") <options>
    -h, --help                      Display help
    --source-file                   Original helm release (may be absent for a new release)
    --target-file                   New helm release
    --remove-common-labels          Remove common labels from manifests
EOF
}

main() {
    local source_file=
    local target_file=
    local remove_common_labels=
    parse_command_line "$@"
    check "helm"
    check "yq"
    entry
}

parse_command_line() {
    while :; do
        case "${1:-}" in
            -h|--help)
                show_help
                exit
                ;;
            --source-file)
                if [[ -n "${2:-}" ]]; then
                    source_file="$2"
                    shift
                else
                    echo "ERROR: '--source-file' cannot be empty." >&2
                    show_help
                    exit 1
                fi
                ;;
            --target-file)
                if [[ -n "${2:-}" ]]; then
                    target_file="$2"
                    shift
                else
                    echo "ERROR: '--target-file' cannot be empty." >&2
                    show_help
                    exit 1
                fi
                ;;
            --remove-common-labels)
                remove_common_labels=true
                ;;
            *)
                break
                ;;
        esac
        shift
    done

    if [[ -z "${source_file}" ]]; then
        echo "ERROR: '--source-file' is required." >&2
        show_help
        exit 1
    fi

    # Files may hold several documents (e.g. OCIRepository + HelmRelease):
    # keep only the HelmRelease so the .spec lookups below are unambiguous.
    if [[ -e "${source_file}" ]]; then
        source_file=$(only_helm_release "${source_file}")
        if [[ ! -s "${source_file}" ]]; then
            echo "ERROR: '--source-file' is not a HelmRelease" >&2
            show_help
            exit 1
        fi
    fi

    if [[ -z "${target_file}" ]]; then
        echo "ERROR: '--target-file' is required." >&2
        show_help
        exit 1
    fi

    original_target_file="${target_file}"
    target_file=$(only_helm_release "${target_file}")
    if [[ ! -s "${target_file}" ]]; then
        echo "ERROR: '--target-file' is not a HelmRelease" >&2
        show_help
        exit 1
    fi

    if [[ -z "$remove_common_labels" ]]; then
        remove_common_labels=false
    fi
}

only_helm_release() {
    local out=
    out=$(mktemp --suffix=.yaml)
    yq eval 'select(.kind == "HelmRelease")' "${1}" > "${out}" 2>/dev/null || true
    echo "${out}"
}

_resources() {
    local chart_name=${1}
    local chart_version=${2}
    local chart_registry_url=${3}
    local chart_values=${4}
    local resources=

    helm repo add main "${chart_registry_url}" > /dev/null 2>&1
    pushd "$(mktemp -d)" > /dev/null 2>&1
    helm pull "main/${chart_name}" --untar --version "${chart_version}"
    resources=$(echo "${chart_values}" | helm template "${chart_name}" "${chart_name}" --version "${chart_version}" -f -)
    if [[ "${remove_common_labels}" == "true" ]]; then
        labels='.metadata.labels."helm.sh/chart"'
        labels+=',.metadata.labels.chart'
        labels+=',.metadata.labels."app.kubernetes.io/version"'
        labels+=',.spec.template.metadata.labels."helm.sh/chart"'
        labels+=',.spec.template.metadata.labels.chart'
        labels+=',.spec.template.metadata.labels."app.kubernetes.io/version"'
        echo "${resources}" | yq eval "del($labels)" -
    else
        echo "${resources}"
    fi
    popd > /dev/null 2>&1
    helm repo remove main > /dev/null 2>&1
}

entry() {
    local comments=

    # Charts referenced through chartRef (OCIRepository) are not supported yet.
    if [[ $(yq eval '.spec.chart.spec.chart // ""' "${target_file}") == "" ]]; then
        # shellcheck disable=SC2016
        printf 'Path: `%s`\n\n```\nSkipped: chart is not referenced via spec.chart.spec (e.g. chartRef/OCIRepository)\n```\n' "${original_target_file}"
        return
    fi

    # Always render the target first. For a newly added HelmRelease this still
    # validates that the chart and values can be rendered successfully.
    target_chart_version=$(chart_version "${target_file}")
    target_chart_name=$(chart_name "${target_file}")
    target_chart_registry_url=$(chart_registry_url "${target_file}")
    target_chart_values=$(chart_values "${target_file}")
    target_resources=$(_resources "${target_chart_name}" "${target_chart_version}" "${target_chart_registry_url}" "${target_chart_values}")
    echo "${target_resources}" > /tmp/target_resources

    # Store the comment in an array
    comments=()

    # shellcheck disable=SC2016
    comments+=( "$(printf 'Path: `%s`' "${original_target_file}")" )

    if [[ ! -e "${source_file}" ]]; then
        # There is no baseline on the default branch for a newly added release.
        # Rendering the target above is the validation in this case.
        # shellcheck disable=SC2016
        comments+=( "$(printf 'Status: `new HelmRelease`')" )
        # shellcheck disable=SC2016
        comments+=( "$(printf 'Chart: `%s`' "${target_chart_name}")" )
        # shellcheck disable=SC2016
        comments+=( "$(printf 'Version: `%s`' "${target_chart_version}")" )
        # shellcheck disable=SC2016
        comments+=( "$(printf 'Registry URL: `%s`' "${target_chart_registry_url}")" )
        comments+=( "$(printf '\n\n')" )
        # shellcheck disable=SC2016
        comments+=( "$(printf '```\nNo previous HelmRelease exists on the default branch.\nTarget chart rendered successfully.\n```')" )
        printf "%s\n" "${comments[@]}"
        return
    fi

    source_chart_name=$(chart_name "${source_file}")
    source_chart_version=$(chart_version "${source_file}")
    source_chart_registry_url=$(chart_registry_url "${source_file}")
    source_chart_values=$(chart_values "${source_file}")
    source_resources=$(_resources "${source_chart_name}" "${source_chart_version}" "${source_chart_registry_url}" "${source_chart_values}")
    echo "${source_resources}" > /tmp/source_resources

    # Diff the files and always return true
    diff -u /tmp/source_resources /tmp/target_resources > /tmp/diff || true
    # Remove the filenames
    sed -i -e '1,2d' /tmp/diff

    if [[ "${source_chart_name}" != "${target_chart_name}" ]]; then
        # shellcheck disable=SC2016
        comments+=( "$(printf 'Chart: `%s` -> `%s`' "${source_chart_name}" "${target_chart_name}")" )
    fi
    if [[ "${source_chart_version}" != "${target_chart_version}" ]]; then
        # shellcheck disable=SC2016
        comments+=( "$(printf 'Version: `%s` -> `%s`' "${source_chart_version}" "${target_chart_version}")" )
    fi
    if [[ "${source_chart_registry_url}" != "${target_chart_registry_url}" ]]; then
        # shellcheck disable=SC2016
        comments+=( "$(printf 'Registry URL: `%s` -> `%s`' "${source_chart_registry_url}" "${target_chart_registry_url}")" )
    fi
    comments+=( "$(printf '\n\n')" )
    if [[ -f /tmp/diff && -s /tmp/diff ]]; then
        # shellcheck disable=SC2016
        comments+=( "$(printf '```diff\n%s\n```' "$(cat /tmp/diff)")" )
    else
        # shellcheck disable=SC2016
        comments+=( "$(printf '```\nNo changes detected in resources\n```')" )
    fi

    # Join the array with a new line and print it
    printf "%s\n" "${comments[@]}"
}

main "$@"
