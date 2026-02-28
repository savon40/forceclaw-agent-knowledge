# Deployment

<!-- TODO: Expand when the bot gains deployment capabilities -->

## Future capabilities

### Deployment methods
- Change sets
- Salesforce CLI (`sf project deploy start`)
- Metadata API
- Unlocked packages / managed packages

### Pre-deployment checklist
- Run all tests
- Verify code coverage (75% minimum, 90%+ recommended)
- Check for hardcoded IDs
- Validate against target org

### Deployment best practices
- Deploy to sandbox first, then production
- Use validation-only deployments to check before committing
- Quick deploy after successful validation
- Rollback strategies
