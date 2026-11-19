# KeyDo 3.83

- **Contact names are read properly**, for Mac Contacts, VCF, CSV, LinkedIn and anything else you import:
  - Titles at the start are not part of the name and are dropped: Dr., Mr., Mrs., Ms., Miss, Shri, Shree, Sri, Smt, Md, Er., Prof, Mohammad (also Mohammed, Muhammad, Mohd).
  - A dash or hyphen ends the name. What follows is kept as extra detail in the contact's notes ("Rahul Shah - Zoho" becomes the name Rahul Shah, note Zoho).
  - A name is never longer than 15 characters. A long one is shortened to the first name and the surname's first letter ("Yogeshwaran S"); the full name is kept in notes.
- **Make shortcuts from contacts** now starts from the first name and includes the picture: `yogesh.pic`, `yogesh.mobile`, `yogesh.email`. If two people share a first name, the second gets `yogeshs.mobile` (more letters of the surname if needed), then a number as the last resort. Existing contacts are read with the same rules when you make shortcuts.
- Keyboard safety: no change to the key watcher.
