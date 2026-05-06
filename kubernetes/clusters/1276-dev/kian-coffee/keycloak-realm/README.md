# Keycloak realm — `kian-coffee` (dev)

Source-of-truth export of the dev `kian-coffee` realm hosted on
`sso.dev.techgarden.gg` (the existing Keycloak instance — both realms cohabit
per `06-auth-keycloak.md`). Re-export with:

```sh
set -a; source ../../../../../../.env; set +a
TOKEN=$(curl -s -X POST "$KEYCLOAK_ADMIN_URL/realms/master/protocol/openid-connect/token" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'client_id=admin-cli' -d 'grant_type=password' \
  -d "username=$KEYCLOAK_ADMIN_USERNAME" \
  --data-urlencode "password=$KEYCLOAK_ADMIN_PASSWORD" \
  | jq -r .access_token)
curl -s -X POST "$KEYCLOAK_ADMIN_URL/admin/realms/kian-coffee/partial-export?exportClients=true&exportGroupsAndRoles=true" \
  -H "Authorization: Bearer $TOKEN" | jq . > realm.json
```

The export deliberately excludes users (per `feedback_keycloak_users.md`).
