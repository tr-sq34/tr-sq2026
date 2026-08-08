import json

with open('ca-current-template.json') as f:
    template = json.load(f)

container = template['containers'][0]
env_map = {e['name']: e for e in container.get('env', [])}

env_map['AZURE_CLIENT_ID'] = {'name': 'AZURE_CLIENT_ID', 'value': '21ccc87a-eaa6-4f19-9fdf-30ca5bafb445'}
env_map['APPLICATIONINSIGHTS_CONNECTION_STRING'] = {'name': 'APPLICATIONINSIGHTS_CONNECTION_STRING', 'value': 'InstrumentationKey=31dacf21-c9e7-40a3-b85e-26aa1c62ed97;IngestionEndpoint=https://centralus-2.in.applicationinsights.azure.com/;LiveEndpoint=https://centralus.livediagnostics.monitor.azure.com/;ApplicationId=15021d49-14a0-407c-99f6-c8e6987f62ec'}

container['env'] = list(env_map.values())

body = {'properties': {'template': template}}
with open('ca-patch-body.json', 'w') as f:
    json.dump(body, f)

print(json.dumps(body, indent=2)[:500])