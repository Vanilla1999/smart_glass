# T2151 Voice Hint and Clarification UX Plan

Status: `ACCEPTED`

## 1. Goal

Give the user a fast and understandable voice path on a small glasses display
without requiring item numbers or a permanent `Listening -> Recognizing ->
Checking` status flow.

The UI must support both:

- a fast highlighted phrase that can be spoken independently;
- arbitrary free-text consisting of one or more parts of the item name.

When free-text matches several items, the user must be able to narrow the
candidate set with another word or phrase instead of repeating the complete
name.

## 2. Core UX Contract

Every displayed selectable item must have exactly one bold voice key.

The bold voice key means:

> This word or phrase can be spoken independently to identify this item in the
> current candidate set.

Examples:

```text
MOCK Белый 1
     ^^^^^ bold

Молоко Простоквашино отборное
       ^^^^^^^^^^^^^^^ bold

Молоко Домик в деревне 3,2%
       ^^^^^^^^^^^^^^^ bold
```

Bold text must not be decorative. The same source of truth must provide the
displayed span, the accepted voice phrase and the target item ID.

## 3. Valid Voice Key

A voice key is valid only when all conditions are satisfied:

- it identifies exactly one item in the complete active candidate set;
- it contains at least one meaningful word;
- it is accepted by the active recognition configuration;
- it does not conflict with a fixed command on the screen;
- it is normalized consistently with `VoiceListMatcher`;
- it remains stable for the lifetime of the displayed candidate set.

A voice key must not be:

- one letter;
- punctuation;
- an incomplete word fragment;
- a standalone number;
- a standalone stop word;
- a word or phrase shared by several active candidates.

Initial Russian stop words include:

```text
в, во, на, для, из, с, со, к, ко, у, о, об, от, до, по, и, а, но
```

A stop word may appear inside a meaningful phrase:

```text
Домик в деревне
^^^^^^^^^^^^^^^^ valid phrase
```

It must not be selected independently:

```text
в
^ invalid key
```

A standalone meaningful word may contain three characters, for example `сыр`
or `чай`. Short tokens still require exact matching and must not be accepted as
fuzzy prefixes.

## 4. Voice Key Selection

For every item, choose the shortest pronounceable key that is unique in the
active candidate set.

Selection order:

1. A unique meaningful word.
2. A unique contiguous two-word phrase.
3. A unique contiguous three-word phrase.
4. A longer unique phrase.
5. The complete unique item name.

During clarification, already spoken words and words shared by all remaining
candidates are excluded from preferred keys. The next bold phrase should show
what is useful to say next.

Example:

```text
Initial candidates:
Молоко Домик в деревне 2,5%
Молоко Домик в деревне 3,2%
Молоко Простоквашино 2,5%

User: "молоко"

Clarification:
Молоко Домик в деревне 2,5%
        ^^^^^^^^^^^^^^^ bold

Молоко Домик в деревне 3,2%
        ^^^^^^^^^^^^^^^ bold

Молоко Простоквашино 2,5%
        ^^^^^^^^^^^^^^^ bold
```

If the user then says `домик`, the list is reduced again and the keys are
recalculated for the remaining candidates.

## 5. Indistinguishable Items

Two items cannot receive unique voice keys when their voice-relevant data is
identical or differs only by forbidden tokens.

Example:

```text
Молоко Домик 2,5
Молоко Домик 3,2
```

If standalone numbers are not allowed, the data source must provide an explicit
pronounceable `voiceLabel` or `voiceAliases`. The UI must not invent a one-letter
or meaningless key just to satisfy the visual contract.

If no valid key can be produced, the item remains selectable through
`up`/`down`/`select`, and the missing voice metadata must be reported as a data
validation issue.

## 6. Free-Text Contract

Bold text is the recommended fast path, not the only accepted speech.

The user may say any meaningful part of an item name:

```text
простоквашино
молоко простоквашино
домик в деревне
молоко домик отборное
```

The matcher must accept one or more words. Every spoken query word must match a
word in the item label or its explicit voice metadata.

The active search scope is the complete logical list, not only the four rows
currently visible on the glasses.

## 7. Progressive Clarification

Clarification is cumulative filtering:

```text
all items
-> "молоко"
-> "домик в деревне"
-> "отборное"
-> one item
```

Each utterance filters the current candidate set. The user does not repeat the
previous phrase.

Required behavior:

- no matches: keep the current candidate set and show `Совпадений нет`;
- unchanged candidate set: show `Назовите точнее`;
- smaller ambiguous set: update the list and recalculate all bold keys;
- one match: select the item;
- back: restore the previous candidate set and its voice keys;
- more than four candidates: keep page navigation commands available.

The existing `WearVoiceClarificationScreen` already supports recursive
candidate filtering and previous-state restoration. The new work adds voice-key
generation, rich display metadata and partial-result feedback.

## 8. Large Lists

Numbers are not required as the primary interaction.

Every visible row still displays its bold voice key. Free-text continues to
search the complete list, including items on other pages.

For large lists:

- arbitrary free-text remains available for all items;
- bold keys provide the recommended phrase for each visible item;
- an ambiguous final result opens clarification;
- the clarification list shows newly useful differentiating phrases;
- `up`, `down`, `select`, `next page` and `previous page` remain fallbacks.

An ambiguous partial must not navigate to clarification while the user is still
speaking. Navigation occurs only after a final decision.

## 9. Partial Feedback

Partial results are feedback, not a business action.

Required behavior:

- stable unique partial: move focus to the matching item;
- stable ambiguous partial: do not navigate; prepare the candidate set only;
- unstable partial: no visible list change;
- final unique result: commit selection;
- final ambiguous result: open clarification.

The first rollout must not select a printer, navigate or print from a free-text
partial. Optimistic selection may be considered only after store validation.

## 10. Visual Rules

Selection and voice hints must remain visually distinct:

- border and selection marker mean current focus;
- bold span means recommended voice key;
- normal text remains speakable as part of free-text;
- previously spoken/common words use normal weight;
- notices use the existing compact one-line list notice.

The payload must carry structured spans or a structured voice hint. Markdown or
embedded markup inside the item label is forbidden.

## 11. Delayed Recognition Notice

Permanent recognition stages are not displayed.

On `VAD_START`, start a 900 ms timer:

- stable useful partial before timeout: cancel the timer and show focus feedback;
- completed action before timeout: cancel the timer;
- no useful partial after timeout: show a compact `Распознаю...` notice;
- final result: clear the notice;
- no match or error: replace it with a short actionable message.

The notice must not cover the list. The existing `_ListNotice` placement above
the list is the preferred presentation.

## 12. UX Acceptance Criteria

- Every displayed item has one meaningful bold voice key or a reported voice
  metadata validation failure.
- No one-letter, stop-word-only or standalone-number key is shown.
- Saying a bold key resolves to exactly one item in the active candidate set.
- Saying multiple parts of a name is supported.
- A second clarification phrase filters the existing candidates instead of
  restarting the search.
- Bold keys are recalculated after every clarification step.
- Stable partial changes focus only.
- Final result owns selection and navigation.
- The delayed notice does not appear for normally fast `up`/`down` commands.
