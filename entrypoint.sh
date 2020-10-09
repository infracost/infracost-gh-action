#!/bin/sh -le

tfjson=$1
tfplan=$2
tfdir=$3
tfflags=$4
percentage_threshold=$5
pricing_api_endpoint=$6

save_infracost_cmd () {
  local infracost_cmd="infracost --no-color --log-level warn"
  if [ ! -z "$tfjson" ]; then
    infracost_cmd="$infracost_cmd --tfjson $1/$tfjson"
  fi
  if [ ! -z "$tfplan" ]; then
    infracost_cmd="$infracost_cmd --tfplan $1/$tfplan"
  fi
  if [ ! -z "$tfdir" ]; then
    infracost_cmd="$infracost_cmd --tfdir $1/$tfdir"
  fi
  if [ ! -z "$tfflags" ]; then
    infracost_cmd="$infracost_cmd --tfflags \"$tfflags\""
  fi
  if [ ! -z "$pricing_api_endpoint" ]; then
    infracost_cmd="$infracost_cmd --pricing_api_endpoint $pricing_api_endpoint"
  fi
  echo "$infracost_cmd" > $1/infracost_cmd
}

dir="/github/workspace/master"
save_infracost_cmd $dir
echo "Running infracost on master branch using:"
echo "  $ $(cat $dir/infracost_cmd)"
master_output=$(cat $dir/infracost_cmd | sh)
echo "$master_output" > master_infracost.txt
master_monthly_cost=$(cat master_infracost.txt | awk '/OVERALL TOTAL/ { print $NF }')
echo "  master_monthly_cost=$master_monthly_cost"
echo "::set-output name=master_monthly_cost::$master_monthly_cost"

dir="/github/workspace/pull_request"
save_infracost_cmd $dir
echo "Running infracost on pull request using:"
echo "  $ $(cat $dir/infracost_cmd)"
pull_request_output=$(cat $dir/infracost_cmd | sh)
echo "$pull_request_output" > pull_request_infracost.txt
pull_request_monthly_cost=$(cat pull_request_infracost.txt | awk '/OVERALL TOTAL/ { print $NF }')
echo "  pull_request_monthly_cost=$pull_request_monthly_cost"
echo "::set-output name=pull_request_monthly_cost::$pull_request_monthly_cost"

percent_diff=$(echo "scale=4; $pull_request_monthly_cost / $master_monthly_cost * 100 - 100" | bc)
absolute_percent_diff=$(echo $percent_diff | tr -d -)

if [ $(echo "$absolute_percent_diff > $percentage_threshold" | bc -l) == 1 ]; then
  change_word="increase"
  if [ $(echo "$percent_diff < 0" | bc -l) == 1 ]; then
    change_word="decrease"
  fi
  echo "Posting GitHub comment as master branch and pull request diff ($absolute_percent_diff) is more than the percentage threshold ($percentage_threshold)."
  jq -Mnc --arg change_word $change_word \
          --arg absolute_percent_diff $(printf '%.1f\n' $absolute_percent_diff) \
          --arg master_monthly_cost $master_monthly_cost \
          --arg pull_request_monthly_cost $pull_request_monthly_cost \
          --arg diff "$(git diff --no-color --no-index master_infracost.txt pull_request_infracost.txt | tail -n +3)" \
          '{body: "Monthly cost estimate will \($change_word) by \($absolute_percent_diff)% (master branch $\($master_monthly_cost) vs pull request $\($pull_request_monthly_cost))\n<details><summary>infracost diff</summary>\n\n```diff\n\($diff)\n```\n</details>\n"}' | \
          curl -sL -X POST -d @- \
            -H "Content-Type: application/json" \
            -H "Authorization: token $GITHUB_TOKEN" \
            "https://api.github.com/repos/$GITHUB_REPOSITORY/commits/$GITHUB_SHA/comments" > /dev/null
else
  echo "GitHub comment not posted as master branch and pull request diff ($absolute_percent_diff) is not more than the percentage threshold ($percentage_threshold)."
fi
