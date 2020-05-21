#!/usr/bin/env bash

set -e
set -o pipefail

# Script for Git repos housing edX services. These repos are mounted as
# data volumes into their corresponding Docker containers to facilitate development.
# Repos are cloned to/removed from the directory above the one housing this file.

if [ -z "$DEVSTACK_WORKSPACE" ]; then
    echo "need to set workspace dir"
    exit 1
elif [ -d "$DEVSTACK_WORKSPACE" ]; then
    cd $DEVSTACK_WORKSPACE
else
    echo "Workspace directory $DEVSTACK_WORKSPACE doesn't exist"
    exit 1
fi

if [ -n "${OPENEDX_RELEASE}" ]; then
    DEFAULT_GIT_BRANCH=open-release/${OPENEDX_RELEASE}
else
    DEFAULT_GIT_BRANCH=master
fi

repos=(
    "https://github.com/edx/course-discovery.git"
    "https://github.com/edx/credentials.git"
    "https://github.com/edx/cs_comments_service.git"
    "https://github.com/ucsd-ets/ecommerce.git develop"
    "https://github.com/edx/edx-e2e-tests.git"
    "https://github.com/edx/edx-notes-api.git"
    "https://github.com/ucsd-ets/edx-platform.git develop"
    "https://github.com/edx/xqueue.git"
    "https://github.com/edx/edx-analytics-pipeline.git"
    "https://github.com/edx/gradebook.git"
)

private_repos=(
    # Needed to run whitelabel tests.
    "https://github.com/edx/edx-themes.git"
)

branch_pattern="\.git (.*)$"
name_pattern=".*/(.*).git"
repo_pattern="(.*/.*\.git)"

_set_repo_params ()
	{
	# Use Bash's regex match operator to capture the name of the repo.
	# Results of the match are saved to an array called $BASH_REMATCH.
	[[ $1 =~ $name_pattern ]]
	name="${BASH_REMATCH[1]}"

	if [[ $1 =~ $branch_pattern ]]
	then
		OPENEDX_GIT_BRANCH="${BASH_REMATCH[1]}"
	else
		OPENEDX_GIT_BRANCH="${DEFAULT_GIT_BRANCH}"
	fi

	[[ $1 =~ $repo_pattern ]]
	repo="${BASH_REMATCH[1]}"
	}

_checkout ()
{
    repos_to_checkout=("$@")

    for repo_full in "${repos_to_checkout[@]}"
    do
		_set_repo_params "$repo_full"

        # If a directory exists and it is nonempty, assume the repo has been cloned.
        if [ -d "$name" -a -n "$(ls -A "$name" 2>/dev/null)" ]; then
            echo "Checking out branch ${OPENEDX_GIT_BRANCH} of $name"
            cd $name
            _checkout_and_update_branch
            cd ..
        fi
    done
}

checkout ()
{
    _checkout "${repos[@]}"
}

_clone ()
{
    # for repo in ${repos[*]}
    repos_to_clone=("$@")
    for repo_full in "${repos_to_clone[@]}"
    do
		echo "$repo_full"
		_set_repo_params "$repo_full"
		echo "Checking out branch $OPENEDX_GIT_BRANCH for repo $repo in directory $name"

        # If a directory exists and it is nonempty, assume the repo has been checked out
        # and only make sure it's on the required branch
        if [ -d "$name" -a -n "$(ls -A "$name" 2>/dev/null)" ]; then
            printf "The [%s] repo is already checked out. Checking for updates.\n" $name
            cd ${DEVSTACK_WORKSPACE}/${name}
            _checkout_and_update_branch
            cd ..
        else
            if [ "${SHALLOW_CLONE}" == "1" ]; then
                git clone -b ${OPENEDX_GIT_BRANCH} -c core.symlinks=true --depth=1 ${repo}
            else
                git clone -b ${OPENEDX_GIT_BRANCH} -c core.symlinks=true ${repo}
            fi
        fi
    done
    cd - &> /dev/null
}

_checkout_and_update_branch ()
{
    GIT_SYMBOLIC_REF="$(git symbolic-ref HEAD 2>/dev/null)"
    BRANCH_NAME=${GIT_SYMBOLIC_REF##refs/heads/}
    if [ "${BRANCH_NAME}" == "${OPENEDX_GIT_BRANCH}" ]; then
        git pull origin ${OPENEDX_GIT_BRANCH}
    else
        git fetch origin ${OPENEDX_GIT_BRANCH}:${OPENEDX_GIT_BRANCH}
        git checkout ${OPENEDX_GIT_BRANCH}
    fi
    find . -name '*.pyc' -not -path './.git/*' -delete 
}

clone ()
{
    _clone "${repos[@]}"
}

clone_private ()
{
    _clone "${private_repos[@]}"
}

reset ()
{
    currDir=$(pwd)
    for repo_full in ${repos[*]}
    do
		_set_repo_params "$repo_full"
		echo "Resetting to master for repo $repo in directory $name"

        if [ -d "$name" ]; then
            cd $name;git reset --hard HEAD;git checkout master;git reset --hard origin/master;git pull;cd "$currDir"
        else
            printf "The [%s] repo is not cloned. Continuing.\n" $name
        fi
    done
    cd - &> /dev/null
}

status ()
{
    currDir=$(pwd)
    for repo in ${repos[*]}
    do
        [[ $repo =~ $name_pattern ]]
        name="${BASH_REMATCH[1]}"

        if [ -d "$name" ]; then
            printf "\nGit status for [%s]:\n" $name
            cd $name;git status;cd "$currDir"
        else
            printf "The [%s] repo is not cloned. Continuing.\n" $name
        fi
    done
    cd - &> /dev/null
}

if [ "$1" == "checkout" ]; then
    checkout
elif [ "$1" == "clone" ]; then
    clone
elif [ "$1" == "whitelabel" ]; then
    clone_private
elif [ "$1" == "reset" ]; then
    read -p "This will override any uncommited changes in your local git checkouts. Would you like to proceed? [y/n] " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        reset
    fi
elif [ "$1" == "status" ]; then
    status
fi
