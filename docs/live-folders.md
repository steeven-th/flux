# Live folders

A live folder fills itself from a source and updates every 30 minutes, when Flux starts, and with
Update Now in its menu. Right-click the favorites and choose New Live Folder….

- **RSS or Atom feed**: the feed's address, or a site's when its pages name their feed.
- **GitHub**: pull requests waiting for your review, your open pull requests, the issues assigned
  to you, or any search written as on github.com, where `@me` stands for you. As on
  github.com/pulls, a search lists open items only unless it says `is:closed` or `is:merged`.

New items come on top with a dot, and the folder shows how many there are. Opening a tab marks it
as read, and Mark All as Read clears them all. A folder keeps the 25 newest items: those gone from
the source leave it, unless a window shows them. A tab removed from the folder stays out of it, and
a tab dragged out of it becomes an ordinary favorite. Stop Updating turns the live folder into an
ordinary folder with the tabs it had.

Flux reads feeds itself, outside the space's profile, so feeds that need a sign-in don't work.

## GitHub

Flux signs in with GitHub's device flow: it shows a code, opens github.com/login/device, and waits
while you type the code there. GitHub's OAuth apps have no read-only scope for private
repositories, so Flux asks for `repo`. It only reads with it. The token stays in your keychain, and
Sign Out removes it.

Builds of Flux need an OAuth app of their own, with the device flow turned on, whose client ID goes
in `GitHubAccount.clientID`.
