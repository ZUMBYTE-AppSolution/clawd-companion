"""Use the platform's credential store for the optional remembered session."""
import json
import sys

def backend():
    if sys.platform == "win32":
        from keyring.backends.Windows import WinVaultKeyring
        return WinVaultKeyring()
    from keyring.backends.SecretService import Keyring
    return Keyring()

SERVICE = "de.zumbyte.clawdcompanion.arena"

def read():
    raw = backend().get_password(SERVICE, "session")
    if raw:
        token, user = json.loads(raw)
        if isinstance(token, str) and isinstance(user, str):
            return token, user
    return "", ""

def save(token, user):
    backend().set_password(SERVICE, "session", json.dumps([token, user]))

def clear():
    store = backend()
    if store.get_password(SERVICE, "session") is not None:
        store.delete_password(SERVICE, "session")
