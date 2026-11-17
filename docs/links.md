# Links

## Links from other apps

Make Flux your default browser in Settings > General, and links you click in other apps open in
Flux.

By default they open in a little window of the current space. Settings > Links can open them as a
new tab instead.

### Rules

Rules in Settings > Links send some links elsewhere. A rule matches on what the link contains, on
the app it comes from, or on both, and opens it in a space of your choice, as a tab or in a little
window. Rules are tried from the top, and the first that matches wins. Right-click a rule to move
it up or down.

For example, a rule can open every `meet.google.com` link in your work space, or every link from
Slack in a little window of your client's space.

The list of apps offers the ones that sent links to Flux before. Choose… picks any other app.
Deleting a space deletes its rules.

### How Flux knows the app

macOS tells Flux which process sent the link. Flux takes the app that process belongs to, so a
link sent by one of an app's helpers counts as coming from the app. Links opened from Terminal
with `open` come from no app, so only rules on the link match them.

## Links opened from a page

A link you open in a new tab from a tab of Today, with ⌘-click, a middle click or a target, goes
below that tab, in its group. Hold ⌥ as you click to open it as a tab of its own instead.
Settings > Links turns grouping off.

To take a tab out of its group, right-click it and choose Remove from Group, or drag it out. Below
the last tab of a group, the drop line follows the dragged tab: moved right, in line with the
group's tabs, it joins the group, moved left it lands below it.
