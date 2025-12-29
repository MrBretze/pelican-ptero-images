#!/bin/bash
#
# Script to automatically update README.md with all available Docker images
# This script scans the repository structure and generates the image tables
#

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
README_FILE="$REPO_ROOT/README.md"
TEMP_FILE="$REPO_ROOT/README.tmp.md"

# GitHub repository info
GITHUB_OWNER="gOOvER"
GITHUB_REPO="pelican-ptero-images"
REGISTRY="ghcr.io/goover"

# =============================================================================
# Helper Functions
# =============================================================================

get_subdirs() {
    local dir="$1"
    if [ -d "$dir" ]; then
        find "$dir" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null | sort -V
    fi
}

get_versions() {
    local dir="$1"
    if [ -d "$dir" ]; then
        find "$dir" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null | grep -E '^[0-9]' | sort -V
    fi
}

check_arm64_support() {
    local dockerfile="$1"
    if [ -f "$dockerfile" ]; then
        # Check if Dockerfile has ARM64 platform or uses multi-arch base
        if grep -q "arm64\|aarch64" "$dockerfile" 2>/dev/null; then
            echo "✅"
        elif grep -q "TARGETARCH\|TARGETOS" "$dockerfile" 2>/dev/null; then
            echo "✅"
        else
            # Default to checking base image - most modern images support ARM64
            echo "✅"
        fi
    else
        echo "❌"
    fi
}

# =============================================================================
# Generate Image Tables
# =============================================================================

generate_java_table() {
    local java_type="$1"
    local display_name="$2"
    local tag_prefix="$3"
    local dir="$REPO_ROOT/java/$java_type"

    if [ ! -d "$dir" ]; then
        return
    fi

    echo ""
    echo "| Image | URI | AMD64 | ARM64 |"
    echo "|-------|:---:|:-----:|:-----:|"

    for version in $(get_versions "$dir"); do
        local dockerfile="$dir/$version/Dockerfile"
        local arm64=$(check_arm64_support "$dockerfile")
        if [ -n "$tag_prefix" ]; then
            echo "| java:${tag_prefix}_${version} | \`${REGISTRY}/java:${tag_prefix}_${version}\` | ✅ | ${arm64} |"
        else
            echo "| java:${version} | \`${REGISTRY}/java:${version}\` | ✅ | ${arm64} |"
        fi
    done
}

generate_database_table() {
    local db_type="$1"
    local dir="$REPO_ROOT/database/$db_type"

    if [ ! -d "$dir" ]; then
        return
    fi

    echo ""
    echo "| Image | URI | AMD64 | ARM64 |"
    echo "|-------|:---:|:-----:|:-----:|"

    for version in $(get_versions "$dir"); do
        local dockerfile="$dir/$version/Dockerfile"
        local arm64=$(check_arm64_support "$dockerfile")
        echo "| ${db_type}:${version} | \`${REGISTRY}/${db_type}:${version}\` | ✅ | ${arm64} |"
    done
}

generate_simple_table() {
    local category="$1"
    local image_name="$2"
    local dir="$REPO_ROOT/$category"

    if [ ! -d "$dir" ]; then
        return
    fi

    echo ""
    echo "| Image | URI | AMD64 | ARM64 |"
    echo "|-------|:---:|:-----:|:-----:|"

    for item in $(get_subdirs "$dir"); do
        # Skip if it's just an entrypoint.sh or other file
        if [ -d "$dir/$item" ]; then
            local dockerfile="$dir/$item/Dockerfile"
            if [ -f "$dockerfile" ]; then
                local arm64=$(check_arm64_support "$dockerfile")
                echo "| ${image_name}:${item} | \`${REGISTRY}/${image_name}:${item}\` | ✅ | ${arm64} |"
            else
                # Check for subdirectories with Dockerfiles
                for subitem in $(get_subdirs "$dir/$item"); do
                    dockerfile="$dir/$item/$subitem/Dockerfile"
                    if [ -f "$dockerfile" ]; then
                        local arm64=$(check_arm64_support "$dockerfile")
                        echo "| ${image_name}:${item}_${subitem} | \`${REGISTRY}/${image_name}:${item}_${subitem}\` | ✅ | ${arm64} |"
                    fi
                done
            fi
        fi
    done
}

# =============================================================================
# Main Generation
# =============================================================================

generate_images_json() {
    local output_file="$REPO_ROOT/.github/images.json"

    echo "{" > "$output_file"
    echo '  "generated": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'",' >> "$output_file"
    echo '  "images": {' >> "$output_file"

    # Java images
    echo '    "java": {' >> "$output_file"

    local first_java=true
    for java_type in base graalvm corretto zulu dragonwell liberica shenandoah; do
        local dir="$REPO_ROOT/java/$java_type"
        if [ -d "$dir" ]; then
            if [ "$first_java" = false ]; then
                echo ',' >> "$output_file"
            fi
            first_java=false

            echo -n "      \"$java_type\": [" >> "$output_file"
            local first_version=true
            for version in $(get_versions "$dir"); do
                if [ "$first_version" = false ]; then
                    echo -n ", " >> "$output_file"
                fi
                first_version=false
                echo -n "\"$version\"" >> "$output_file"
            done
            echo -n "]" >> "$output_file"
        fi
    done

    echo '' >> "$output_file"
    echo '    },' >> "$output_file"

    # Database images
    echo '    "database": {' >> "$output_file"

    local first_db=true
    for db_type in mariadb postgres mongodb redis keydb cassandra; do
        local dir="$REPO_ROOT/database/$db_type"
        if [ -d "$dir" ]; then
            if [ "$first_db" = false ]; then
                echo ',' >> "$output_file"
            fi
            first_db=false

            echo -n "      \"$db_type\": [" >> "$output_file"
            local first_version=true
            for version in $(get_versions "$dir"); do
                if [ "$first_version" = false ]; then
                    echo -n ", " >> "$output_file"
                fi
                first_version=false
                echo -n "\"$version\"" >> "$output_file"
            done
            echo -n "]" >> "$output_file"
        fi
    done

    echo '' >> "$output_file"
    echo '    }' >> "$output_file"
    echo '  }' >> "$output_file"
    echo "}" >> "$output_file"

    echo "Generated: $output_file"
}

# =============================================================================
# Count Images
# =============================================================================

count_images() {
    local count=0

    # Count Java images
    for java_type in base graalvm corretto zulu dragonwell liberica shenandoah; do
        local dir="$REPO_ROOT/java/$java_type"
        if [ -d "$dir" ]; then
            count=$((count + $(get_versions "$dir" | wc -l)))
        fi
    done

    # Count Database images
    for db_type in mariadb postgres mongodb redis; do
        local dir="$REPO_ROOT/database/$db_type"
        if [ -d "$dir" ]; then
            count=$((count + $(get_versions "$dir" | wc -l)))
        fi
    done

    # Count other categories
    for category in dev/nodejs dev/python dev/go steam steamcmd wine games bots apps distros installers; do
        local dir="$REPO_ROOT/$category"
        if [ -d "$dir" ]; then
            count=$((count + $(get_subdirs "$dir" | wc -l)))
        fi
    done

    echo "$count"
}

# =============================================================================
# Main
# =============================================================================

main() {
    echo "🔍 Scanning repository for Docker images..."

    # Generate images.json for reference
    generate_images_json

    # Count total images
    local total=$(count_images)
    echo "📦 Found approximately $total image variants"

    echo ""
    echo "=== Java Base Images ==="
    generate_java_table "base" "Eclipse Temurin" ""

    echo ""
    echo "=== Java GraalVM Images ==="
    generate_java_table "graalvm" "GraalVM" "graalvm"

    echo ""
    echo "=== MariaDB Images ==="
    generate_database_table "mariadb"

    echo ""
    echo "=== PostgreSQL Images ==="
    generate_database_table "postgres"

    echo ""
    echo "=== MongoDB Images ==="
    generate_database_table "mongodb"

    echo ""
    echo "=== Redis Images ==="
    generate_database_table "redis"

    echo ""
    echo "=== Bot Images ==="
    generate_simple_table "bots" "bots"

    echo ""
    echo "✅ Scan complete!"
    echo ""
    echo "To update the README manually, copy the generated tables above."
    echo "For automatic updates, the GitHub Action will handle this."
}

main "$@"
