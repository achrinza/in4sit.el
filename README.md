<!--
    SDPX-FileCopyrightText: 2025 Rifa Achrinza <public-foss-in4sit.el@achrinza.com>
    SPDX-License-Identifier: FSFAP
-->

# in4sit.el

> [!WARNING]
> This is an early prototype. Expect errors, omissions, and breaking changes.

> [!WARNING]
> Windows Emacs users only - Please save all work on your Emacs instance
> before executing the `in4sit-class-schedule` function. There is a
> long-standing bug in the built-in `url` package that causes Emacs to hang if
> a network connection is never established.

> [!NOTE]
> Not endorsed by Singapore Institute of Technology, Oracle or PeopleSoft.

Unofficial data retriever and extractor for Singapore Institute of
Technology's IN4SIT Oracle PeopleSoft instance.

## Features

- Retrieve data
    - class schedule
- Generate [Org](https://orgmode.org/) file items with `SCHEDULE`s,
  `DEADLINE`s, and properties
- Convert class schedule (meeting patterns) into concrete events
- `auth-source` credential retrieval

## Notable Missing Features

An unordered list of planned, important features:

- Extract across mulitple terms (tri-/se-mesters) in one go
- Extract exam schedules
- Generate iCalendar (`.ics`) files
- Synchronous data retrieval

## Prerequisite: Configuring SIT ADFS credentials

This package leverages `auth-source`. For a basic setup, add the following
line into `~/.authinfo`, replacing the user id and password with your own:

```netrc
machine fs.singaporetech.edu.sg port adfs login 1234567@sit.singaporetech.edu.sg secret "MyPassword123!"
```

> [!WARNING]
> Although this is good for quick testing, leaving credentials accessible in 
> plaintext is not really secure. Consider either using a PGP-encrypted
> `.authinfo.gpg`or an alternate `auth-source` backend instead. See the
> [auth-source
> docs](https://www.gnu.org/software/emacs/manual/html_mono/auth.html) for
> more guidance.

The credentials are only sent directly to SIT's identity provider
<https://fs.singaporetech.edu.sg>. This package will not transmit them
anywhere else. Transmission of credentials is only ever handled by the
`in4sit--submit-login-request` function.

## Recipes

### Extract class schedule and dump into a buffer

<!--
    SPDX-SnippetBegin
    SPDX-SnippetCopyrightText 2025 Rifa Achrinza <public-foss-in4sit.el@achrinza.com>
    SDPX-License-Identifier: GPL-3.0-or-later
-->
```elisp
(defun my-callback (courses)
  (with-current-buffer (generate-new-buffer (generate-new-buffer-name "sit-class-schedules"))
    (insert (format "%s" courses))
    (pp-buffer)
    (pop-to-buffer (current-buffer))))
(in4sit-class-schedule 'my-callback)
```
<!--
    SPDX-SnippetEnd
-->


### Extract class schedule and dump it to Org format

<!--
    SPDX-SnippetBegin
    SPDX-SnippetCopyrightText 2025 Rifa Achrinza <public-foss-in4sit.el@achrinza.com>
    SDPX-License-Identifier: GPL-3.0-or-later
-->
```elisp
(defun my-callback (courses)
  (pop-to-buffer (in4sit-class-schedule-to-org-agenda courses)))
(in4sit-class-schedule 'my-callback)
```
<!--
    SPDX-SnippetEnd
-->

## License

[GPL 3.0 or later](./LICENSES/GPL-3.0-or-later.txt) and [FSFAP](./LICENSES/FSFAP.txt)
