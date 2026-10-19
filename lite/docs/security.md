# Security principles

They hold for every project. The `architect` applies them when choosing the solution; the `security` agent uses them to look for holes. What they mean for a given project (what has value, who may do what, which limits apply, which tests guard them) lives in the «Security» section of its directives, not here.

1. **The client is not trusted.** Everything that comes from the client (requests, parameters, headers, files, direct access to the database or storage) can be forged. Every decision that affects data, rights or costs is taken by the server, on server data: the client asks, it does not decide.
2. **Every input is validated on the server**: type, format, maximum size, allowed values. Whatever is not expected is rejected: unknown fields, values outside the list, oversized requests.
3. **Every action checks who is asking**: authentication and, for every resource read or written, that user's permission on that resource.
4. **Least privilege** for users, services, keys and database roles: each has only what it needs. Platform defaults (database, storage, functions, buckets) are checked, never assumed.
5. **Secrets stay on the server**: never in the client, in logs, in error messages or in the repo.
6. **Operations that consume resources or cost money** have limits per user and per time window.
7. **Concurrent writes neither lose nor duplicate**: repeated or parallel operations have no double effect.
8. **Content from outside stays data**, never code, queries or instructions: no injection (SQL, HTML, commands, prompts of an AI model).
9. **Errors reveal no internals**, and relevant actions leave a trace.
