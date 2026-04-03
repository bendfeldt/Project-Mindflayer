# Azure DevOps Pipeline Templates for Terraform

Reference for CI/CD pipeline patterns using Azure DevOps YAML pipelines.
Load this reference when the project uses Azure DevOps for Terraform automation.

## Pipeline Structure

Organize pipelines as reusable templates. The pattern is:

```
pipelines/
├── templates/
│   ├── terraform-init.yml        # Shared init step
│   ├── terraform-plan.yml        # Plan with artifact publish
│   ├── terraform-apply.yml       # Apply from saved plan
│   └── terraform-destroy.yml     # Destroy (manual trigger only)
├── infrastructure-ci.yml         # Triggered on PR (validate + plan)
└── infrastructure-cd.yml         # Triggered on merge (plan + approve + apply)
```

## CI Pipeline (PR Validation)

Runs on every pull request. Validates and plans, but never applies.

```yaml
# pipelines/infrastructure-ci.yml
trigger: none
pr:
  branches:
    include:
      - main
  paths:
    include:
      - terraform/**

pool:
  vmImage: 'ubuntu-latest'

variables:
  - group: terraform-common            # Service connection, backend config
  - name: workingDirectory
    value: 'terraform/environments/dev'

stages:
  - stage: Validate
    displayName: 'Terraform Validate'
    jobs:
      - job: Validate
        steps:
          - template: templates/terraform-init.yml
            parameters:
              workingDirectory: $(workingDirectory)
              backendServiceConnection: $(backendServiceConnection)
              backendResourceGroup: $(backendResourceGroup)
              backendStorageAccount: $(backendStorageAccount)
              backendContainer: $(backendContainer)
              backendKey: 'dev.tfstate'

          - task: Bash@3
            displayName: 'Terraform Format Check'
            inputs:
              targetType: inline
              workingDirectory: $(workingDirectory)
              script: terraform fmt -check -recursive

          - task: Bash@3
            displayName: 'Terraform Validate'
            inputs:
              targetType: inline
              workingDirectory: $(workingDirectory)
              script: terraform validate

  - stage: Plan
    displayName: 'Terraform Plan (Dev)'
    dependsOn: Validate
    jobs:
      - job: Plan
        steps:
          - template: templates/terraform-plan.yml
            parameters:
              workingDirectory: $(workingDirectory)
              environment: dev
```

## CD Pipeline (Deploy)

Triggered on merge to main. Plans each environment, waits for approval, then applies.

```yaml
# pipelines/infrastructure-cd.yml
trigger:
  branches:
    include:
      - main
  paths:
    include:
      - terraform/**

pool:
  vmImage: 'ubuntu-latest'

variables:
  - group: terraform-common

stages:
  # --- DEV: auto-apply ---
  - stage: PlanDev
    displayName: 'Plan Dev'
    jobs:
      - template: templates/terraform-plan.yml
        parameters:
          environment: dev

  - stage: ApplyDev
    displayName: 'Apply Dev'
    dependsOn: PlanDev
    jobs:
      - deployment: ApplyDev
        environment: 'terraform-dev'       # No approval gate for dev
        strategy:
          runOnce:
            deploy:
              steps:
                - template: templates/terraform-apply.yml
                  parameters:
                    environment: dev

  # --- TEST: manual approval ---
  - stage: PlanTest
    displayName: 'Plan Test'
    dependsOn: ApplyDev
    jobs:
      - template: templates/terraform-plan.yml
        parameters:
          environment: test

  - stage: ApplyTest
    displayName: 'Apply Test'
    dependsOn: PlanTest
    jobs:
      - deployment: ApplyTest
        environment: 'terraform-test'      # Approval gate configured in ADO
        strategy:
          runOnce:
            deploy:
              steps:
                - template: templates/terraform-apply.yml
                  parameters:
                    environment: test

  # --- PROD: manual approval ---
  - stage: PlanProd
    displayName: 'Plan Prod'
    dependsOn: ApplyTest
    jobs:
      - template: templates/terraform-plan.yml
        parameters:
          environment: prod

  - stage: ApplyProd
    displayName: 'Apply Prod'
    dependsOn: PlanProd
    jobs:
      - deployment: ApplyProd
        environment: 'terraform-prod'      # Stricter approval gate
        strategy:
          runOnce:
            deploy:
              steps:
                - template: templates/terraform-apply.yml
                  parameters:
                    environment: prod
```

## Reusable Templates

### Init Template

```yaml
# pipelines/templates/terraform-init.yml
parameters:
  - name: workingDirectory
    type: string
  - name: backendServiceConnection
    type: string
  - name: backendResourceGroup
    type: string
  - name: backendStorageAccount
    type: string
  - name: backendContainer
    type: string
  - name: backendKey
    type: string

steps:
  - task: TerraformInstaller@1
    displayName: 'Install Terraform'
    inputs:
      terraformVersion: 'latest'

  - task: AzureCLI@2
    displayName: 'Terraform Init'
    inputs:
      azureSubscription: ${{ parameters.backendServiceConnection }}
      scriptType: bash
      scriptLocation: inlineScript
      workingDirectory: ${{ parameters.workingDirectory }}
      addSpnToEnvironment: true
      inlineScript: |
        export ARM_CLIENT_ID=$servicePrincipalId
        export ARM_CLIENT_SECRET=$servicePrincipalKey
        export ARM_TENANT_ID=$tenantId
        terraform init \
          -backend-config="resource_group_name=${{ parameters.backendResourceGroup }}" \
          -backend-config="storage_account_name=${{ parameters.backendStorageAccount }}" \
          -backend-config="container_name=${{ parameters.backendContainer }}" \
          -backend-config="key=${{ parameters.backendKey }}"
```

### Plan Template

```yaml
# pipelines/templates/terraform-plan.yml
parameters:
  - name: environment
    type: string

steps:
  - task: AzureCLI@2
    displayName: 'Terraform Plan (${{ parameters.environment }})'
    inputs:
      azureSubscription: $(backendServiceConnection)
      scriptType: bash
      workingDirectory: 'terraform/environments/${{ parameters.environment }}'
      addSpnToEnvironment: true
      inlineScript: |
        export ARM_CLIENT_ID=$servicePrincipalId
        export ARM_CLIENT_SECRET=$servicePrincipalKey
        export ARM_TENANT_ID=$tenantId
        terraform plan -out=tfplan -input=false

  - task: PublishPipelineArtifact@1
    displayName: 'Publish Plan Artifact'
    inputs:
      targetPath: 'terraform/environments/${{ parameters.environment }}/tfplan'
      artifact: 'tfplan-${{ parameters.environment }}'
```

### Apply Template

```yaml
# pipelines/templates/terraform-apply.yml
parameters:
  - name: environment
    type: string

steps:
  - task: DownloadPipelineArtifact@2
    displayName: 'Download Plan'
    inputs:
      artifact: 'tfplan-${{ parameters.environment }}'
      path: 'terraform/environments/${{ parameters.environment }}'

  - task: AzureCLI@2
    displayName: 'Terraform Apply (${{ parameters.environment }})'
    inputs:
      azureSubscription: $(backendServiceConnection)
      scriptType: bash
      workingDirectory: 'terraform/environments/${{ parameters.environment }}'
      addSpnToEnvironment: true
      inlineScript: |
        export ARM_CLIENT_ID=$servicePrincipalId
        export ARM_CLIENT_SECRET=$servicePrincipalKey
        export ARM_TENANT_ID=$tenantId
        terraform apply -input=false tfplan
```

## Variable Groups

Use Azure DevOps variable groups to manage per-environment secrets:

- `terraform-common` — shared settings (service connection name, backend storage account)
- `terraform-dev` — dev-specific overrides
- `terraform-prod` — prod-specific (link to Key Vault for secrets)

Variable group linked to Key Vault:
Settings → Variable groups → Link secrets from Azure Key Vault
This way secrets are never stored in ADO — they're fetched at pipeline runtime.
