import pathlib

path = pathlib.Path('tr-sq2026-bootstrap/infra/terraform/azure/modules/container-app/main.tf')
corrupt = path.read_text(encoding='utf-8')

block = '''      dynamic "env" {
        for_each = var.secret_env
        iterator = secret_env
        content {
          name        = secret_env.value.env_name
          secret_name = secret_env.value.name
        }
      }'''

parts = corrupt.split(block)

if parts and parts[0] == '':
    parts = parts[1:]
if parts and parts[-1] == '':
    parts = parts[:-1]

original = ''.join(parts)

print('Parts count (including empty ends):', len(parts) + 2)
print('Original length:', len(original), 'chars')
print('--- FIRST 700 chars ---')
print(original[:700])
print('--- LAST 300 chars ---')
print(original[-300:])
print('--- LINE COUNT ---')
print(len(original.splitlines()))

out_path = pathlib.Path('tmp/main.tf.reconstructed')
out_path.write_text(original, encoding='utf-8')
print('Wrote reconstructed preview to:', out_path)
