$ErrorActionPreference = "Stop"

$ScriptRoot   = Split-Path -Parent $MyInvocation.MyCommand.Path
$BucketName   = "togglemaster-tfstate-fase-003"
$Region       = "us-east-1"
$InfraDir     = Join-Path $ScriptRoot "terraform\environments\prod\infra"
$BootstrapDir = Join-Path $ScriptRoot "terraform\environments\prod\bootstrap"
$AwsCmd       = "C:\Program Files\Amazon\AWSCLIV2\aws.exe"

if (-not (Test-Path $AwsCmd)) {
    Write-Error "AWS CLI nao encontrada em: $AwsCmd"
    exit 1
}

Write-Host "====================================================="
Write-Host " ToggleMaster Fase 3 - Full Bootstrap"
Write-Host "====================================================="

Write-Host "Validando credenciais AWS..."
try {
    & $AwsCmd sts get-caller-identity | Out-Null
    Write-Host "Credenciais AWS OK."
}
catch {
    Write-Error "Falha ao validar credenciais AWS. Verifique a sessao/perfil do AWS Academy."
    exit 1
}

Write-Host "Verificando bucket do backend remoto..."
$bucketExists = $true

try {
    & $AwsCmd s3api head-bucket --bucket $BucketName 2>$null
    if ($LASTEXITCODE -ne 0) {
        $bucketExists = $false
    }
}
catch {
    $bucketExists = $false
}

if (-not $bucketExists) {
    Write-Host "Bucket nao existe ou nao esta acessivel. Tentando criar..."

    try {
        if ($Region -eq "us-east-1") {
            & $AwsCmd s3api create-bucket --bucket $BucketName
        } else {
            & $AwsCmd s3api create-bucket `
                --bucket $BucketName `
                --region $Region `
                --create-bucket-configuration LocationConstraint=$Region
        }

        & $AwsCmd s3api put-bucket-versioning `
            --bucket $BucketName `
            --versioning-configuration Status=Enabled

        Write-Host "Bucket criado com versionamento."
    }
    catch {
        Write-Error "Falha ao criar/configurar o bucket S3. Verifique permissoes e nome global do bucket."
        exit 1
    }
}
else {
    Write-Host "Bucket ja existe."
}

Write-Host ""
Write-Host "==== ETAPA 1: INFRA AWS ===="
Set-Location $InfraDir
terraform init
terraform validate
terraform plan -out=tfplan
terraform apply -auto-approve tfplan

Write-Host ""
Write-Host "==== ETAPA 2: BOOTSTRAP K8S ===="
Set-Location $BootstrapDir
terraform init
terraform validate
terraform plan -out=tfplan
terraform apply -auto-approve tfplan

Write-Host ""
Write-Host "==== FINALIZADO ===="