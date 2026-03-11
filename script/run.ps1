
## Create App Registration automatically (recommended)

## Run in PowerShell:
./Create-AppRegistration.ps1

## Save the output values:
## - TenantId
## - ClientId
## - ClientSecret

## Running the Tenant Health Report
## Run in PowerShell, replace the placeholders with the actual values from the previous step:

./TenantHealthReport.ps1 `
-TenantId "<TENANT-ID>" `
-ClientId "<CLIENT-ID>" `
-ClientSecret "<CLIENT-SECRET>"

## Output

## The script generates an HTML file in the current directory:

## TenantHealth_YYYYMMDD_HHMMSS.html
