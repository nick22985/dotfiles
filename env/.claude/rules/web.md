---
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs,vue,svelte}"
---

## Web

### Data Fetching
- **Search, filter, sort and paginate on the server:** never fetch a whole collection to search, filter, sort or page it in the frontend unless I explicitly ask. Lists are paginated by the API (limit/skip plus a total count), and queries run in the database.
- **Return only what the view needs:** select the fields a list or picker uses instead of returning full documents.
- **Derived values:** if a filter or sort depends on a computed value (e.g. "last assessed"), store that value on the record when it's saved so it can be queried, rather than computing it client-side over everything.
- **Existing client-side lists:** when extending a list that already does this in the browser, say so and propose moving it server-side instead of building on it.
