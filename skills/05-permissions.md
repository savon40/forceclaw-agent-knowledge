# Permissions & Access

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

## Tips for permission questions

- When a user asks "who can see X", remember that access is **additive** — check profiles AND permission sets AND sharing rules
- When debugging "why can't I do X", work top-down: Object permissions → Field permissions → Record sharing → Validation rules
- **Validation rules can block edits even if permissions allow them** — always check validation rules if the user says "I have access but can't save"
- Use `describe_object` to see if a field is required, unique, or has other constraints
