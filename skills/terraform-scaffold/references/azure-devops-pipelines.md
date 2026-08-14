# Azure DevOps Terraform pipeline

Use pinned tools, OIDC workload identity, saved plans, and environment approvals. The service connection must use workload identity federation.

```yaml
trigger:
  branches:
    include: [main]
pr:
  branches:
    include: [main]

pool:
  vmImage: ubuntu-latest

variables:
  terraformVersion: 1.12.2
  workingDirectory: terraform

stages:
  - stage: Validate
    jobs:
      - job: TerraformValidate
        steps:
          - task: TerraformInstaller@1
            inputs:
              terraformVersion: $(terraformVersion)
          - script: terraform fmt -check -recursive
            workingDirectory: $(workingDirectory)
          - script: terraform init -backend=false
            workingDirectory: $(workingDirectory)
          - script: terraform validate
            workingDirectory: $(workingDirectory)

  - stage: Plan
    dependsOn: Validate
    condition: and(succeeded(), ne(variables['Build.Reason'], 'PullRequest'))
    jobs:
      - job: TerraformPlan
        steps:
          - task: AzureCLI@2
            inputs:
              azureSubscription: workload-identity-service-connection
              scriptType: bash
              scriptLocation: inlineScript
              workingDirectory: $(workingDirectory)
              inlineScript: |
                terraform init -input=false
                terraform plan -input=false -out=tfplan
          - task: PublishPipelineArtifact@1
            inputs:
              targetPath: $(workingDirectory)/tfplan
              artifact: terraform-plan

  - stage: Apply
    dependsOn: Plan
    condition: succeeded()
    jobs:
      - deployment: TerraformApply
        environment: production-infrastructure
        strategy:
          runOnce:
            deploy:
              steps:
                - download: current
                  artifact: terraform-plan
                - task: AzureCLI@2
                  inputs:
                    azureSubscription: workload-identity-service-connection
                    scriptType: bash
                    scriptLocation: inlineScript
                    workingDirectory: $(workingDirectory)
                    inlineScript: terraform apply -input=false tfplan
```

Configure approval checks on the Azure DevOps environment. Keep backend identifiers and non-sensitive environment values in protected pipeline variables; resolve secrets from Key Vault. Do not pass client secrets to Terraform.
