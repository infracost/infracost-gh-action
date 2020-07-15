#!/bin/sh -l

echo $TERRAFORM_DIR

master_output=$(infracost --no-color --tfdir /github/workspace/master/$TERRAFORM_DIR)
echo "$master_output"
echo "$master_output" > master_infracost.txt
master_monthly_cost=$(echo $master_output | awk '/OVERALL TOTAL/ { print $NF }')
echo "::set-output name=master_monthly_cost::$master_monthly_cost"

pull_request_output=$(infracost --no-color --tfdir /github/workspace/pull_request/$TERRAFORM_DIR)
echo "$pull_request_output"
echo "$pull_request_output" > pull_request_infracost.txt
pull_request_monthly_cost=$(echo $pull_request_output | awk '/OVERALL TOTAL/ { print $NF }')
echo "::set-output name=pull_request_monthly_cost::$pull_request_monthly_cost"

if [ $master_monthly_cost -eq $pull_request_monthly_cost]; then
  jq -Mnc --arg diff "$(git diff --no-color --no-index master_infracost.txt pull_request_infracost.txt | tail -n +3)" '{body: "Master branch monthly cost estimate $master_monthly_cost\nPull request monthly cost estimate $pull_request_monthly_cost\n<details><summary>Infracost diff</summary>\n\n```diff\n\($diff)\n```\n</details>\n"}' | \
  curl -sL -X POST -d @- \
    -H "Content-Type: application/json" \
    -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/$GITHUB_REPOSITORY/commits/$GITHUB_SHA/comments"
else
  echo "GitHub comment not posted as master branch and pull_request have the same cost estimate."
fi
