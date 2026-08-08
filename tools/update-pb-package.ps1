$sasUrl = 'https://stpasswordbreachchprodcu.blob.core.windows.net/function-releases/password-breach-check-latest.zip?se=2027-08-06T04%3A43%3A47Z&sp=r&spr=https&sv=2026-04-06&sr=b&sig=XGIFdEwm1gQJcnafpiD2ecxr4V%2Bbs6n6ImTOrwvMsBI%3D'
az functionapp config appsettings set --name func-password-breach-check-prod-cu --resource-group rg-turksquare-prod-centralus --settings "WEBSITE_RUN_FROM_PACKAGE=$sasUrl" -o none
az functionapp restart --name func-password-breach-check-prod-cu --resource-group rg-turksquare-prod-centralus -o none
