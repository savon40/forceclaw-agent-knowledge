# Permissions & Access

## CRITICAL: Field-Level Security vs Object Permissions

**Object CRUD permissions (Create, Read, Edit, Delete, View All, Modify All) do NOT grant access to individual fields.**

Even with full CRUD + Modify All on an object, a user CANNOT see or edit a custom field unless Field-Level Security (FLS) is explicitly granted for that field on their profile or permission set.

When a user asks to "grant edit access to all fields" on a permission set or profile:
1. **Call `describe_object`** to get the complete list of ALL fields — especially custom fields ending in `__c`
2. **Use `update_permission_set_field_permissions`** for EACH custom field to grant read and/or edit access
3. **Do NOT skip this step** — object-level permissions alone are NOT enough for field access
4. **System fields** (Id, CreatedDate, CreatedById, LastModifiedDate, SystemModstamp, IsDeleted, LastActivityDate) get their visibility from object permissions — no FLS needed
5. **Custom fields** (anything ending in `__c`) MUST have FLS set explicitly — they default to NO access

**NEVER tell the user** that "Modify All" or "View All" permissions on the object mean they can access all fields. That is INCORRECT. FLS is always separate from object permissions.

**NEVER say** an object has no custom fields without first calling `describe_object` to verify. The org context summary only lists object names — it does NOT list fields.

---

## Common questions and how to answer them

Permissions questions are the most frequent category in production orgs. Users ask things like:
- "Who has access to the Bonus__c field?"
- "What permissions does the Sales Team profile have?"
- "Why can't Jane edit Opportunities?"

## Permission model overview

Salesforce permissions are **additive** — access is granted, never subtracted. A user's effective permissions come from the combination of:

1. **Profile** — base permissions (every user has exactly one)
2. **Permission Sets** — additional permissions layered on top
3. **Permission Set Groups** — bundles of permission sets
4. **Sharing Rules** — record-level access (who can see which records)
5. **Role Hierarchy** — managers inherit subordinates' record access

## Useful queries

### Find a user's profile and permission sets
```sql
SELECT Id, Name, Profile.Name,
  (SELECT PermissionSet.Name, PermissionSet.Label
   FROM PermissionSetAssignments
   WHERE PermissionSet.IsOwnedByProfile = false)
FROM User
WHERE Name = 'Jane Smith'
LIMIT 1
```

### List all permission sets in the org
```sql
SELECT Id, Name, Label, Description
FROM PermissionSet
WHERE IsOwnedByProfile = false
ORDER BY Label
LIMIT 200
```

### Who has a specific permission set?
```sql
SELECT Assignee.Name, Assignee.Email, Assignee.IsActive
FROM PermissionSetAssignment
WHERE PermissionSet.Name = 'Sales_Operations'
ORDER BY Assignee.Name
LIMIT 200
```

### What object permissions does a permission set grant?
```sql
SELECT SobjectType, PermissionsCreate, PermissionsRead,
       PermissionsEdit, PermissionsDelete, PermissionsViewAllRecords,
       PermissionsModifyAllRecords
FROM ObjectPermissions
WHERE ParentId IN (
  SELECT Id FROM PermissionSet WHERE Name = 'Sales_Operations'
)
ORDER BY SobjectType
LIMIT 200
```

### What field-level security does a permission set grant?
```sql
SELECT Field, SobjectType, PermissionsRead, PermissionsEdit
FROM FieldPermissions
WHERE ParentId IN (
  SELECT Id FROM PermissionSet WHERE Name = 'Sales_Operations'
)
AND SobjectType = 'Opportunity'
ORDER BY Field
LIMIT 200
```

### Who has access to a specific field? (field-level security)
```sql
SELECT Parent.Name, Parent.Label, Parent.IsOwnedByProfile,
       PermissionsRead, PermissionsEdit
FROM FieldPermissions
WHERE SobjectType = 'Opportunity'
  AND Field = 'Opportunity.Bonus__c'
  AND (PermissionsRead = true OR PermissionsEdit = true)
ORDER BY Parent.Label
LIMIT 200
```
This returns both profiles (where `IsOwnedByProfile = true`) and permission sets.

### "Why can't [user] edit [object]?"

To debug access issues, check these in order:

1. **Profile object permissions** — does the profile grant Edit on the object?
```sql
SELECT SobjectType, PermissionsEdit
FROM ObjectPermissions
WHERE ParentId IN (
  SELECT Id FROM PermissionSet
  WHERE IsOwnedByProfile = true
  AND ProfileId IN (SELECT ProfileId FROM User WHERE Name = 'Jane Smith')
)
AND SobjectType = 'Opportunity'
```

2. **Permission set object permissions** — do any assigned permission sets grant Edit?
```sql
SELECT Parent.Label, PermissionsEdit
FROM ObjectPermissions
WHERE ParentId IN (
  SELECT PermissionSetId FROM PermissionSetAssignment
  WHERE Assignee.Name = 'Jane Smith'
)
AND SobjectType = 'Opportunity'
```

3. **Record ownership / sharing** — can the user see the specific record?
   - Check the OwnerId of the record
   - Check if the user's role is above the owner's role in the hierarchy
   - Check sharing rules on the object

4. **Field-level security** — even with object Edit, individual fields may be read-only
```sql
SELECT Field, PermissionsEdit
FROM FieldPermissions
WHERE ParentId IN (
  SELECT PermissionSetId FROM PermissionSetAssignment
  WHERE Assignee.Name = 'Jane Smith'
)
AND SobjectType = 'Opportunity'
AND PermissionsEdit = false
ORDER BY Field
```

## Sharing rules

### List sharing rules on an object (via Tooling API)
```sql
SELECT Id, DeveloperName, SobjectType, Description
FROM SharingRules
WHERE SobjectType = 'Account'
```

### Role hierarchy
The role hierarchy determines record-level visibility. Managers can see records owned by users below them in the hierarchy.

```sql
SELECT Id, Name, ParentRoleId, ParentRole.Name
FROM UserRole
ORDER BY Name
LIMIT 200
```

To see what role a specific user has:
```sql
SELECT Name, UserRole.Name
FROM User
WHERE Name = 'Jane Smith'
LIMIT 1
```

## Writing permission sets (sandbox/dev orgs only)

In sandbox and developer orgs, you can create and modify permission sets using the Metadata API tools.

### Creating a permission set
- Use `create_permission_set` with a DeveloperName (underscores, no spaces) and a label
- Example: name `Sales_Data_Access`, label `Sales Data Access`
- This creates an empty permission set — you then add object and field permissions separately

### Adding object permissions
- Use `update_permission_set_object_permissions` to set CRUD flags for a specific object
- You must specify all four CRUD booleans: `allow_create`, `allow_read`, `allow_edit`, `allow_delete`
- Optionally set `view_all_records` and `modify_all_records` (default false)
- This uses a read-modify-write pattern — it reads the current PS, merges the change, then saves

### Adding field-level security
- Use `update_permission_set_field_permissions` to grant read/edit access to specific fields
- The `field` parameter must be in `Object.FieldName` format (e.g. `Account.Industry`, `Custom__c.My_Field__c`)
- Set `readable` and `editable` booleans
- If editable is true, readable should also be true (you can't edit what you can't see)

### Assigning/unassigning permission sets
- Use `assign_permission_set` with the DeveloperName and a Salesforce User ID (18-char, starts with `005`)
- If you don't have the User ID, query for it first: `SELECT Id, Name FROM User WHERE Name = '...'`
- Use `unassign_permission_set` to remove the assignment
- The tool checks for existing assignments to avoid duplicates

### Important: Permission sets are additive
- Permission sets can only **grant** access — they cannot revoke access granted by the profile or other permission sets
- If a user has too much access, you need to check their profile and other permission sets — removing a PS only removes what that specific PS granted

## Tips for permission questions

- When a user asks "who can see X", remember that access is **additive** — check profiles AND permission sets AND sharing rules
- When debugging "why can't I do X", work top-down: Object permissions → Field permissions → Record sharing → Validation rules
- **Validation rules can block edits even if permissions allow them** — always check validation rules if the user says "I have access but can't save"
- Use `describe_object` to see if a field is required, unique, or has other constraints

## Permission Set Groups

Permission Set Groups (PSGs) bundle multiple permission sets together for easier assignment. Instead of assigning 5 individual permission sets to every sales user, create a `Sales_Team` PSG.

### Querying Permission Set Groups
```sql
-- List all PSGs
SELECT Id, DeveloperName, MasterLabel, Status, Description
FROM PermissionSetGroup
ORDER BY MasterLabel
LIMIT 200
```

```sql
-- What permission sets are in a group?
SELECT PermissionSetGroup.MasterLabel, PermissionSet.Name, PermissionSet.Label
FROM PermissionSetGroupComponent
WHERE PermissionSetGroup.DeveloperName = 'Sales_Team'
```

```sql
-- Who is assigned to a PSG?
SELECT Assignee.Name, Assignee.Email, Assignee.IsActive
FROM PermissionSetAssignment
WHERE PermissionSetGroupId IN (
    SELECT Id FROM PermissionSetGroup WHERE DeveloperName = 'Sales_Team'
)
ORDER BY Assignee.Name
```

### PSG best practices
- **Organize by role**: `Sales_Team`, `Finance_Team`, `Support_Team`
- **Keep individual PSs granular**: Each PS grants one capability (e.g., `Invoice_Full_Access`, `Report_Builder`)
- **Combine in PSGs**: Group related PSs for role-based assignment
- **Status values**: `Updated` (ready to use), `Outdated` (recalculating after a change)

## Permission model layers — complete picture

```
USER's effective access = Profile + Permission Sets + PSGs + Sharing Rules + Role Hierarchy
```

| Layer | What it controls | How it works |
|---|---|---|
| **Profile** | Base permissions (one per user) | Defines default object/field access, system permissions. Legacy — minimize use. |
| **Permission Sets** | Additional permissions (additive only) | Grants object CRUD, field FLS, Apex class access, Custom Permissions, Tab visibility |
| **Permission Set Groups** | Bundles of permission sets | Simplifies assignment — assign one PSG instead of many PSs |
| **Sharing Rules** | Record-level access | Criteria-based or owner-based sharing. Org-Wide Defaults set the baseline (Private, Public Read Only, Public Read/Write) |
| **Role Hierarchy** | Record visibility inheritance | Managers see records owned by subordinates. Only affects objects with OWD = Private or Public Read Only |

### Permission types explained
| Type | Values | What it controls |
|---|---|---|
| Object permissions | Create, Read, Edit, Delete, View All, Modify All | Whether the user can perform CRUD on the object at all |
| Field-Level Security | Read, Edit | Whether the user can see/modify a specific field (Edit implies Read) |
| Setup Entity Access | ApexClass, ApexPage, Flow, CustomPermission | Access to specific platform features |
| System permissions | ViewSetup, ModifyAllData, ViewAllData, ManageUsers, ApiEnabled | Admin-level org permissions |

### Important: Object CRUD ≠ field visibility
Granting Read on Account does NOT mean the user can see all Account fields. You must ALSO grant field-level Read on each field they need to see. When creating new custom fields, they are only visible to System Administrator by default — you must explicitly grant FLS via permission sets.

## Advanced permission debugging

### "Who can delete Accounts?"
```sql
-- Find all permission sets (including profile-based) that grant Delete on Account
SELECT Parent.Name, Parent.Label, Parent.IsOwnedByProfile,
       PermissionsCreate, PermissionsRead, PermissionsEdit, PermissionsDelete,
       PermissionsViewAllRecords, PermissionsModifyAllRecords
FROM ObjectPermissions
WHERE SobjectType = 'Account'
  AND PermissionsDelete = true
ORDER BY Parent.Label
```

### Check for system-level overrides
Some system permissions override object-level permissions:
```sql
-- Find who has ModifyAllData (can modify any record regardless of sharing/FLS)
SELECT Parent.Name, Parent.Label
FROM PermissionSet
WHERE PermissionsModifyAllData = true
```

```sql
-- Find who has ViewAllData
SELECT Parent.Name, Parent.Label
FROM PermissionSet
WHERE PermissionsViewAllData = true
```

### Check Custom Permissions
Custom Permissions are used in code to gate features:
```sql
SELECT SetupEntityId, SetupEntityType, Parent.Name, Parent.Label
FROM SetupEntityAccess
WHERE SetupEntityType = 'CustomPermission'
  AND Parent.IsOwnedByProfile = false
ORDER BY Parent.Label
```
