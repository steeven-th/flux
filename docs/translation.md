# Translation

Flux translates in two ways.

- **Selected text**: select some text in a page, right-click it and choose Translate Selection.
  macOS translates it in its own popover. Nothing to set up.
- **Whole pages**: right-click a page and choose Translate Page. This needs a key for a
  translation service, set in Settings > General > Page Translation. Without a key the item
  doesn't show.

Chromium's own page translation needs Google keys that only Chrome and its partners have, so it
doesn't work in Flux. Apple's Translation framework works on the Mac, but it translates about one
sentence per second, which takes minutes for a long page.

The key is kept in your macOS keychain. Pages you translate are sent to the service you chose.

## DeepL

The free plan translates 500,000 characters a month.

1. Go to [deepl.com/pro-api](https://www.deepl.com/pro-api) and sign up for the DeepL API Free
   plan.
2. Open your account's API Keys page and copy the key. Free keys end with `:fx`.
3. Paste it in Settings > General > Page Translation, with DeepL as the service, then click Test.

Test shows how many characters you used this month, as DeepL counts them.

## Google Cloud Translation

The first 500,000 characters each month are free. Google then charges 20 USD per million
characters. Google Cloud asks for a billing account even to stay within the free part.

1. In the [Google Cloud console](https://console.cloud.google.com), create a project and link a
   billing account to it.
2. Enable the [Cloud Translation API](https://console.cloud.google.com/apis/library/translate.googleapis.com)
   for the project.
3. In APIs & Services > Credentials, create an API key. Restrict it to the Cloud Translation API.
4. Paste it in Settings > General > Page Translation, with Google Cloud Translation as the
   service, then click Test.

Google doesn't tell how much a key used, so Flux counts the characters it sends and Test shows
that count. A budget alert in the Google Cloud console warns you before you pay anything.

For an idea of the size of things, a long Wikipedia article is about 60,000 characters, a news
article a few thousand. Texts that repeat on a page, like menu items, are sent once.
