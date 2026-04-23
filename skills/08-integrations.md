# Integrations

## Current capabilities

- Query and describe External Objects
- Help users understand integration architecture and patterns
- Advise on Named Credentials, callout patterns, and event-driven architecture

## Integration pattern selection guide

| Scenario | Pattern | Why |
|---|---|---|
| Real-time request/response to external API | REST Callout (synchronous) | Immediate response needed, <120s timeout |
| Fire-and-forget notification to external system | Platform Event | Decoupled, reliable delivery, async |
| Track changes to Salesforce records externally | Change Data Capture (CDC) | Near real-time, captures all field changes |
| Process data in background after trigger | Queueable + Callout | Cannot make callouts from triggers directly |
| Bulk data sync on schedule | Batch Apex + Callout | Handle large volumes with governor limit safety |
| External system pushes data TO Salesforce | REST/SOAP Web Service (Apex) | Inbound endpoint in Salesforce |
| High-volume real-time events between systems | Platform Events (High Volume) | Millions/day, 24-hour replay |

## Named Credentials — ALWAYS use these

**NEVER hardcode API endpoints, credentials, or tokens in Apex code.** Always use Named Credentials.

### What Named Credentials do
- Store the endpoint URL and authentication in Salesforce setup (not in code)
- Automatically inject auth headers into callouts
- Support credential rotation without code changes
- Portable between orgs (endpoint URL is configurable per environment)

### Architecture (API 61+)
```
External Credential (auth config: OAuth, API Key, etc.)
  └── Named Credential (endpoint URL + references External Credential)
       └── Permission Set (grants access to use the credential)
```

### Authentication types
| Type | When to use |
|---|---|
| OAuth 2.0 Client Credentials | Server-to-server, no user context needed |
| OAuth 2.0 JWT Bearer | Certificate-based, high-security server-to-server |
| OAuth 2.0 Authorization Code | Per-user auth, user context needed |
| Basic Auth / API Key | Simple APIs, legacy systems |
| Certificate (Mutual TLS) | High-security, mutual authentication |

### Using Named Credentials in Apex
```apex
HttpRequest req = new HttpRequest();
// callout: prefix tells Salesforce to use the Named Credential
req.setEndpoint('callout:My_Named_Credential/api/v1/accounts');
req.setMethod('GET');
req.setHeader('Content-Type', 'application/json');

Http http = new Http();
HttpResponse res = http.send(req);

if (res.getStatusCode() == 200) {
    // Process response
    Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
}
```

## REST callout patterns

### Synchronous REST callout
Use when you need an immediate response and the call completes within timeout limits.

```apex
public class ExternalApiService {
    public static Map<String, Object> getAccount(String externalId) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:My_API/accounts/' + externalId);
        req.setMethod('GET');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(30000); // 30 seconds

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() == 200) {
            return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        } else {
            throw new CalloutException('API error: ' + res.getStatusCode() + ' ' + res.getBody());
        }
    }
}
```

### Async callout (from triggers/flows)
Triggers cannot make callouts directly. Use Queueable for async callouts:

```apex
public class ApiCalloutQueueable implements Queueable, Database.AllowsCallouts {
    private Set<Id> recordIds;

    public ApiCalloutQueueable(Set<Id> recordIds) {
        this.recordIds = recordIds;
    }

    public void execute(QueueableContext context) {
        List<Account> accounts = [SELECT Id, Name, External_Id__c FROM Account WHERE Id IN :recordIds];
        for (Account acc : accounts) {
            // Make callout for each record
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:My_API/sync');
            req.setMethod('POST');
            req.setBody(JSON.serialize(acc));
            new Http().send(req);
        }
    }
}
```

Enqueue from a trigger handler:
```apex
System.enqueueJob(new ApiCalloutQueueable(accountIds));
```

### Retry pattern with exponential backoff
For transient failures (timeouts, 5xx errors):

```apex
public class RetryableCallout {
    private static final Integer MAX_RETRIES = 3;

    public static HttpResponse sendWithRetry(HttpRequest req) {
        Integer attempts = 0;
        HttpResponse res;

        while (attempts < MAX_RETRIES) {
            try {
                res = new Http().send(req);
                if (res.getStatusCode() < 500) {
                    return res; // Success or client error (don't retry 4xx)
                }
            } catch (CalloutException e) {
                if (attempts == MAX_RETRIES - 1) throw e;
            }
            attempts++;
            // Note: Can't actually sleep in Apex — for retries, use Queueable chaining
        }
        return res;
    }
}
```

## Platform Events

Use Platform Events for decoupled, event-driven communication between Salesforce and external systems (or between Salesforce components).

### When to use Platform Events
| Use case | Why Platform Events |
|---|---|
| Notify external system of Salesforce changes | Decoupled, reliable, async |
| Trigger processing across Salesforce automation | No tight coupling between automations |
| Replace Outbound Messages | More flexible, supports custom payloads |
| Replace polling | External systems subscribe via CometD/Pub/Sub API |

### Publishing events from Apex
```apex
// Create and publish a Platform Event
Order_Event__e event = new Order_Event__e(
    Order_Id__c = orderId,
    Action__c = 'Created',
    Payload__c = JSON.serialize(orderData)
);
Database.SaveResult result = EventBus.publish(event);
if (!result.isSuccess()) {
    System.debug(LoggingLevel.ERROR, 'Event publish failed: ' + result.getErrors());
}
```

### Publishing events from Flow
Use a `Create Records` element with the Platform Event object (e.g., `Order_Event__e`).

### Subscribing to events
- **Apex Trigger**: `trigger OrderEventTrigger on Order_Event__e (after insert) { ... }`
- **Flow**: Platform Event-Triggered Flow (triggerType = `PlatformEvent`)
- **External System**: Pub/Sub API (gRPC) or CometD streaming

### Platform Event best practices
- **Batch events** — publish multiple events in a single `EventBus.publish()` call
- **Check publish results** — `SaveResult.isSuccess()` for each event
- **Use timestamps** — include `CreatedDateTime` in the event for ordering
- **Keep payloads small** — Long Text Area fields max 131,072 chars
- **Publish behavior**: `PublishAfterCommit` (default, safer) vs `PublishImmediately` (for error events)
- **Durability**: Events are retained for 24 hours. Use `ReplayId` to resume from last processed event.

## Change Data Capture (CDC)

CDC publishes change events when Salesforce records are created, updated, deleted, or undeleted. External systems subscribe to these events.

### CDC vs Platform Events
| Feature | CDC | Platform Events |
|---|---|---|
| Payload | Automatic (changed fields) | Custom (you define fields) |
| Objects | Standard + Custom objects | Custom event objects |
| Configuration | Enable per object in Setup | Create event definition |
| Use case | Track record changes externally | Custom event-driven messaging |

### CDC event structure
Each change event includes:
- `ChangeEventHeader`: `changeType` (CREATE, UPDATE, DELETE, UNDELETE), `changedFields`, `entityName`, `recordIds`
- Field values: Only changed fields are included (for UPDATE)

### Subscribing to CDC in Apex
```apex
trigger AccountChangeEventTrigger on AccountChangeEvent (after insert) {
    for (AccountChangeEvent event : Trigger.new) {
        EventBus.ChangeEventHeader header = event.ChangeEventHeader;
        String changeType = header.getChangeType();
        List<String> recordIds = header.getRecordIds();

        if (changeType == 'UPDATE') {
            List<String> changedFields = header.getChangedFields();
            // Process changed fields
        }
    }
}
```

## Integration security rules

1. **NEVER hardcode credentials** — use Named Credentials or Custom Metadata for secrets
2. **No synchronous callouts from triggers** — use Queueable, @future(callout=true), or Platform Events
3. **Set explicit timeouts** — default is 10s, max is 120s. Set based on expected response time
4. **Plan for failures** — external systems go down. Implement retry logic or event-based recovery
5. **Use middleware for high volume** — if you need to sync 100K+ records regularly, consider MuleSoft, Heroku, or a dedicated integration platform
6. **Validate external data** — never trust data from external APIs. Validate and sanitize before inserting into Salesforce
7. **Prefer External Credentials** (API 61+) over Legacy Named Credentials for new development

## Governor limits for integrations

| Limit | Synchronous | Asynchronous |
|---|---|---|
| Callouts per transaction | 100 | 100 |
| Total callout time | 120 seconds | 120 seconds |
| Maximum request/response size | 6 MB | 12 MB |
| Concurrent long-running callouts | 10 | 10 |
| Platform Events published per transaction | 150 | 150 |
| Platform Events published per hour (standard volume) | ~2,000 | ~2,000 |
| Platform Events published per hour (high volume) | Millions | Millions |
