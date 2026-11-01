## SOPS / AGE Setup

Using Kubapp `secrets` require SOPS and an AGE key.

KUBAPP expects the AGE key at:

```text
~/.config/sops/age/keys.txt
```

### Setup

Use the provided script:

```bash
bash scripts/extra/setup_sops.sh
```

Or create the key manually:

```bash
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
```

### Configure `setup.env`

Retrieve the private key:

```bash
grep '^AGE-SECRET-KEY-' ~/.config/sops/age/keys.txt
```

Add it to `setup.env`:

```bash
AGE_PRIVATE_KEY="AGE-SECRET-KEY-1..."
```

### Configure `.sops.yaml`

Retrieve the AGE public key:

```bash
grep -oE 'age1[a-z0-9]+' ~/.config/sops/age/keys.txt
```

Add it to the appropriate `creation_rules`:

```yaml
creation_rules:
  - path_regex: gitops/secrets/.*\.ya?ml$
    encrypted_regex: '^(data|stringData)$'
    age: age1...
```

After `setup.env` and `.sops.yaml` are configured, KUBAPP handles the SOPS
workflow through its setup and pre-push configuration.

**Never commit `AGE_PRIVATE_KEY` or plaintext secrets.**
