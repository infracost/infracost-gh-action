#!/bin/sh -l

terraform_dir=$1
percentage_threshold=$2
echo "Using terraform_dir=$terraform_dir and percentage_threshold=$percentage_threshold"

echo "Running infracost on master branch..."
master_output=$(infracost --no-color --tfdir /github/workspace/master/$terraform_dir)
echo "$master_output"
echo "$master_output" > master_infracost.txt
master_monthly_cost=$(echo $master_output | awk '/OVERALL TOTAL/ { print $NF }')
echo "::set-output name=master_monthly_cost::$master_monthly_cost"

echo "Running infracost on pull_request..."
pull_request_output=$(infracost --no-color --tfdir /github/workspace/pull_request/$terraform_dir)
echo "$pull_request_output"
echo "$pull_request_output" > pull_request_infracost.txt
pull_request_monthly_cost=$(echo $pull_request_output | awk '/OVERALL TOTAL/ { print $NF }')
echo "::set-output name=pull_request_monthly_cost::$pull_request_monthly_cost"

absolute_percent_diff=$(echo "scale=4; $master_monthly_cost / $pull_request_monthly_cost * 100 - 100" | bc | tr -d -)

if [ $(echo "$absolute_percent_diff >= $percentage_threshold" | bc -l) == 1 ]; then
  jq -Mnc --arg diff "$(git diff --no-color --no-index master_infracost.txt pull_request_infracost.txt | tail -n +3)" '{body: "Master branch monthly cost estimate $master_monthly_cost\nPull request monthly cost estimate $pull_request_monthly_cost\n<details><summary>Infracost diff</summary>\n\n```diff\n\($diff)\n```\n</details>\n"}' | \
  curl -sL -X POST -d @- \
    -H "Content-Type: application/json" \
    -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/$GITHUB_REPOSITORY/commits/$GITHUB_SHA/comments"
else
  echo "GitHub comment not posted as master branch and pull_request diff ($absolute_percent_diff) was less than the percentage threshold ($percentage_threshold)."
fi
