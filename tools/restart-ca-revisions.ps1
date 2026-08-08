$revs = az containerapp revision list --name ca-identity-prod --resource-group rg-turksquare-prod-centralus --query '[].name' -o tsv
foreach ($r in $revs) {
    if ([string]::IsNullOrWhiteSpace($r)) { continue }
    Write-Host "Restarting revision: $r"
    az containerapp revision restart --name ca-identity-prod --resource-group rg-turksquare-prod-centralus --revision $r
}
