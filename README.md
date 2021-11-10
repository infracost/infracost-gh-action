# Infracost GitHub Action

This GitHub Action runs [Infracost](https://infracost.io) against pull requests whenever Terraform files change. It automatically adds a pull request comment showing the cost estimate difference for the planned state. See [this repo for a demo](https://github.com/infracost/gh-actions-demo).

The Action uses the latest version of Infracost by default as we regularly add support for more cloud resources. If you run into any issues, please join our [community Slack channel](https://www.infracost.io/community-chat); we'd be happy to guide you through it.

As mentioned in our [FAQ](https://infracost.io/docs/faq), no cloud credentials or secrets are sent to the Cloud Pricing API. Infracost does not make any changes to your Terraform state or cloud resources.

<img src="screenshot.png" width=557 alt="Example screenshot" />

## Table of Contents

* [Usage methods](#usage-methods)
  * [Terraform directory](#1-terraform-directory)
  * [Terraform plan JSON](#2-terraform-plan-json)
* [Inputs](#inputs)
* [Environment variables](#environment-variables)
* [Outputs](#outputs)
* [Contributing](#contributing)

# Usage methods

Assuming you have [downloaded Infracost](https://www.infracost.io/docs/#quick-start) and ran `infracost register` to get an API key, there are two methods of using the Infracost GitHub Action:

1. **Terraform directory**, this is the simplest method. However, we recommend the second method if you run into issues relating to `terraform init` or `terraform plan`.

2. **Terraform plan JSON**, this uses the [setup-terraform](https://github.com/hashicorp/setup-terraform) GitHub Action to first generate a plan JSON file then passes that to the Infracost GitHub Action using the `path` input.

## 1. Terraform directory

1. [Add repo secrets](https://docs.github.com/en/actions/configuring-and-managing-workflows/creating-and-storing-encrypted-secrets#creating-encrypted-secrets-for-a-repository) for `INFRACOST_API_KEY` and any other required credentials to your GitHub repo (e.g. `AWS_ACCESS_KEY_ID`).

2. Create a new file in `.github/workflows/infracost.yml` in your repo with the following content. Use the [Inputs](#inputs) and [Environment Variables](#environment-variables) section below to decide which `env` and `with` options work for your Terraform setup. The following example uses `path` to specify the location of the Terraform directory and `terraform_plan_flags` to specify the variables file to use when running `terraform plan`. The GitHub Actions [docs](https://docs.github.com/en/actions/reference/workflow-syntax-for-github-actions#on) describe other options for `on`, though `pull_request` is probably what you want.

  ```yml
  on:
    pull_request:
      paths:
      - '**.tf'
      - '**.tfvars'
      - '**.tfvars.json'
  jobs:
    infracost:
      runs-on: ubuntu-latest
      name: Show infracost diff
      steps:
      - name: Check out repository
        uses: actions/checkout@v2
      - name: Run infracost diff
        uses: infracost/infracost-gh-action@master # Use a specific version instead of master if locking is preferred
        env:
          INFRACOST_API_KEY: ${{ secrets.INFRACOST_API_KEY }}
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }} # Do not change
          # See the cloud credentials section for the options
        with:
          path: path/to/code
          terraform_plan_flags: -var-file=my.tfvars
  ```

3. Send a new pull request to change something in Terraform that costs money; a comment should be posted on the pull request. Check the GitHub Actions logs and [this page](https://www.infracost.io/docs/integrations/cicd#cicd-troubleshooting) if there are issues.

## 2. Terraform plan JSON

1. [Add repo secrets](https://docs.github.com/en/actions/configuring-and-managing-workflows/creating-and-storing-encrypted-secrets#creating-encrypted-secrets-for-a-repository) for `INFRACOST_API_KEY`.

2. Create a new file in `.github/workflows/infracost.yml` in your repo with the following content. Update `path/to/code` to point to your Terraform directory. Also customize the Terraform init/plan steps, and use the [Inputs](#inputs) and [Environment Variables](#environment-variables) section below as required.

  ```yml
  on:
    pull_request:
      paths:
      - '**.tf'
      - '**.tfvars'
      - '**.tfvars.json'
  jobs:
    infracost:
      runs-on: ubuntu-latest
      name: Show infracost diff
      steps:
      - name: Check out repository
        uses: actions/checkout@v2

      - name: "Install terraform"
        uses: hashicorp/setup-terraform@v1

      - name: "Terraform init"
        id: init
        run: terraform init
        working-directory: path/to/code

      - name: "Terraform plan"
        id: plan
        run: terraform plan -out plan.tfplan
        working-directory: path/to/code

      - name: "Terraform show"
        id: show
        run: terraform show -json plan.tfplan
        working-directory: path/to/code
        
      - name: "Save Plan JSON"
        run: echo '${{ steps.show.outputs.stdout }}' > plan.json # Do not change

      - name: Run infracost diff
        uses: infracost/infracost-gh-action@master # Use a specific version instead of master if locking is preferred
        env:
          INFRACOST_API_KEY: ${{ secrets.INFRACOST_API_KEY }}
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          path: plan.json # Do not change as this file is generated above
  ```

3. Send a new pull request to change something in Terraform that costs money; a comment should be posted on the pull request. Check the GitHub Actions logs and [this page](https://www.infracost.io/docs/integrations/cicd#cicd-troubleshooting) if there are issues.

# Inputs

## `path`

**Optional** Path to the Terraform directory or JSON/plan file. Either `path` or `config_file` is required.

## `terraform_plan_flags`

**Optional** Flags to pass to the 'terraform plan' command, e.g. `"-var-file=my.tfvars -var-file=other.tfvars"`. Applicable when path is a Terraform directory.

## `terraform_workspace`

**Optional** The Terraform workspace to use. Applicable when path is a Terraform directory. Only set this for multi-workspace deployments, otherwise it might result in the Terraform error "workspaces not supported".

## `usage_file`

**Optional** Path to Infracost [usage file](https://www.infracost.io/docs/usage_based_resources#infracost-usage-file) that specifies values for usage-based resources, see [this example file](https://github.com/infracost/infracost/blob/master/infracost-usage-example.yml) for the available options.

## `config_file`

**Optional** If your repo has **multiple Terraform projects or workspaces**, define them in a [config file](https://www.infracost.io/docs/config_file/) and set this input to its path. Their results will be combined into the same diff output. Cannot be used with path, terraform_plan_flags or usage_file inputs. 

## `show_skipped`

**Optional** Show unsupported resources, some of which might be free, at the bottom of the Infracost output (default is false).

## `post_condition`

**Optional** A JSON string describing the condition that triggers pull request comments, can be one of these:
- `'{"update": true}'`: we suggest you start with this option. When a commit results in a change in cost estimates vs earlier commits, the integration will create **or update** a PR comment (not commit comments). The GitHub comments UI can be used to see when/what was changed in the comment. PR followers will only be notified on the comment create (not update), and the comment will stay at the same location in the comment history. This is the default behavior for GitHub, please let us know if you'd like to see this for GitLab and BitBucket.
- `'{"has_diff": true}'`: a commit comment is put on the first commit with a Terraform change (i.e. there is a diff) and on every subsequent commit (regardless of whether or not there is a Terraform change in the particular commit). This is the current default for GitLab, BitBucket and Azure Repos (git).
- `'{"always": true}'`: a commit comment is put on every commit.
- `'{"percentage_threshold": 0}'`: absolute percentage threshold that triggers a comment. For example, set to 1 to post a comment if the cost estimate changes by more than plus or minus 1%. A commit comment is put on every commit with a Terraform change that results in a cost diff that is bigger than the threshold.

Please use [this GitHub discussion](https://github.com/infracost/infracost/discussions/1016) to tell us what you'd like to see in PR comments.

## `sync_usage_file` (experimental)

**Optional**  If set to `true` this will create or update the usage file with missing resources, either using zero values or pulling data from AWS CloudWatch. For more information see the [Infracost docs here](https://www.infracost.io/docs/usage_based_resources#1-generate-usage-file). You must also specify the `usage_file` input if this is set to `true`.

# Environment variables

This section describes the main environment variables that can be used in this GitHub Action. Other supported environment variables are described in the [this page](https://www.infracost.io/docs/integrations/environment_variables). [Repo secrets](https://docs.github.com/en/actions/configuring-and-managing-workflows/creating-and-storing-encrypted-secrets#creating-encrypted-secrets-for-a-repository) can be used for sensitive environment values.

Terragrunt users should also read [this page](https://www.infracost.io/docs/iac_tools/terragrunt). Terraform Cloud/Enterprise users should also read [this page](https://www.infracost.io/docs/iac_tools/terraform_cloud_enterprise).

## `INFRACOST_API_KEY`

**Required** To get an API key [download Infracost](https://www.infracost.io/docs/#quick-start) and run `infracost register`.

## `GITHUB_TOKEN`

**Required** GitHub token used to post comments, should be set to `${{ secrets.GITHUB_TOKEN }}` to use the default GitHub token available to actions (see example in the [Usage section](#usage)).

## Cloud credentials

**Required** You do not need to set cloud credentials if you use Terraform Cloud/Enterprise's remote execution mode, instead you should follow [this page](https://www.infracost.io/docs/iac_tools/terraform_cloud_enterprise).

For all other users, the following is needed so Terraform can run `init`:
- Azure users should read [this section](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/service_principal_client_secret) to see which environment variables work for their use-case.
- AWS users should set `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`, or read [this section](https://registry.terraform.io/providers/hashicorp/aws/latest/docs#environment-variables) of the Terraform docs for other options.
- GCP users should set `GOOGLE_CREDENTIALS`, or read [this section](https://registry.terraform.io/providers/hashicorp/google/latest/docs/guides/provider_reference#full-reference) of the Terraform docs for other options.

### Multiple AWS credentials

If your Terraform project uses multiple AWS credentials you can create separate secrets for the different AWS credentials and configure it in your GitHub action using the [Infracost config file](https://www.infracost.io/docs/multi_project/config_file) like below.

**infracost.yml:**

```yml
version: 0.1
projects:
  - path: myproject/dev
    env:
      AWS_ACCESS_KEY_ID: ${DEV_AWS_ACCESS_KEY_ID}
      AWS_SECRET_ACCESS_KEY: ${DEV_AWS_SECRET_ACCESS_KEY}
  - path: myproject/prod
    env:
      AWS_ACCESS_KEY_ID: ${PROD_AWS_ACCESS_KEY_ID}
      AWS_SECRET_ACCESS_KEY: ${PROD_AWS_SECRET_ACCESS_KEY}
```

**.github/workflows/infracost.yml**:

```yml
on:
  pull_request:
    paths:
    - '**.tf'
    - '**.tfvars'
    - '**.tfvars.json'
jobs:
  infracost:
    runs-on: ubuntu-latest
    name: Show infracost diff
    steps:
    - name: Check out repository
      uses: actions/checkout@v2

    - name: Run infracost diff
      uses: infracost/infracost-gh-action@master
      env:
        DEV_AWS_ACCESS_KEY_ID: ${{ secrets.DEV_AWS_ACCESS_KEY_ID }}
        DEV_AWS_SECRET_ACCESS_KEY: ${{ secrets.DEV_AWS_SECRET_ACCESS_KEY }}
        PROD_AWS_ACCESS_KEY_ID: ${{ secrets.PROD_AWS_ACCESS_KEY_ID }}
        PROD_AWS_SECRET_ACCESS_KEY: ${{ secrets.PROD_AWS_SECRET_ACCESS_KEY }}
        INFRACOST_API_KEY: ${{ secrets.INFRACOST_API_KEY }}
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      with:
        config_file: infracost.yml
```

## `INFRACOST_TERRAFORM_BINARY`

**Optional** Used to change the path to the `terraform` binary or version, see [this page](https://www.infracost.io/docs/integrations/environment_variables/#cicd-integrations) for the available options.

## `GIT_SSH_KEY`

**Optional** If you're using Terraform modules from private Git repositories you can set this environment variable to your private Git SSH key so Terraform can access your module.

## `SLACK_WEBHOOK_URL`

**Optional** Set this to also post the pull request comment to a [Slack Webhook](https://slack.com/intl/en-tr/help/articles/115005265063-Incoming-webhooks-for-Slack), which should post it in the corresponding Slack channel.

# Outputs

## `total_monthly_cost`

The new total monthly cost estimate.

## `past_total_monthly_cost`

The past total monthly cost estimate.

## Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

## License

[Apache License 2.0](https://choosealicense.com/licenses/apache-2.0/)
