-- sd-phone orphan audit  (READ ONLY - no writes, safe to run on a live database)
--
-- One row per parent/child relationship. orphan_rows = child rows whose parent no longer exists.
-- Every relationship must report 0 before its FOREIGN KEY can be added: ALTER TABLE ... ADD
-- FOREIGN KEY fails outright if even one orphan is present.
--
-- If a table does not exist yet on your install, MySQL will error on that line - delete it and
-- re-run; it just means the app has never been used.

SELECT 'darkchat_bans.room_id -> darkchat_rooms.id' AS relationship,
       COUNT(*) AS orphan_rows
FROM `darkchat_bans` c
LEFT JOIN `darkchat_rooms` p ON p.`id` = c.`room_id`
WHERE c.`room_id` IS NOT NULL AND p.`id` IS NULL
UNION ALL
SELECT 'darkchat_members.room_id -> darkchat_rooms.id' AS relationship,
       COUNT(*) AS orphan_rows
FROM `darkchat_members` c
LEFT JOIN `darkchat_rooms` p ON p.`id` = c.`room_id`
WHERE c.`room_id` IS NOT NULL AND p.`id` IS NULL
UNION ALL
SELECT 'darkchat_messages.room_id -> darkchat_rooms.id' AS relationship,
       COUNT(*) AS orphan_rows
FROM `darkchat_messages` c
LEFT JOIN `darkchat_rooms` p ON p.`id` = c.`room_id`
WHERE c.`room_id` IS NOT NULL AND p.`id` IS NULL
UNION ALL
SELECT 'darkchat_reactions.message_id -> darkchat_messages.id' AS relationship,
       COUNT(*) AS orphan_rows
FROM `darkchat_reactions` c
LEFT JOIN `darkchat_messages` p ON p.`id` = c.`message_id`
WHERE c.`message_id` IS NOT NULL AND p.`id` IS NULL
UNION ALL
SELECT 'phone_app_sessions.account_id -> phone_app_accounts.id' AS relationship,
       COUNT(*) AS orphan_rows
FROM `phone_app_sessions` c
LEFT JOIN `phone_app_accounts` p ON p.`id` = c.`account_id`
WHERE c.`account_id` IS NOT NULL AND p.`id` IS NULL
UNION ALL
SELECT 'phone_birdy_likes.post_id -> phone_birdy_posts.id' AS relationship,
       COUNT(*) AS orphan_rows
FROM `phone_birdy_likes` c
LEFT JOIN `phone_birdy_posts` p ON p.`id` = c.`post_id`
WHERE c.`post_id` IS NOT NULL AND p.`id` IS NULL
UNION ALL
SELECT 'phone_birdy_notifications.post_id -> phone_birdy_posts.id' AS relationship,
       COUNT(*) AS orphan_rows
FROM `phone_birdy_notifications` c
LEFT JOIN `phone_birdy_posts` p ON p.`id` = c.`post_id`
WHERE c.`post_id` IS NOT NULL AND p.`id` IS NULL
UNION ALL
SELECT 'phone_birdy_reposts.post_id -> phone_birdy_posts.id' AS relationship,
       COUNT(*) AS orphan_rows
FROM `phone_birdy_reposts` c
LEFT JOIN `phone_birdy_posts` p ON p.`id` = c.`post_id`
WHERE c.`post_id` IS NOT NULL AND p.`id` IS NULL
UNION ALL
SELECT 'phone_cherry_messages.match_id -> phone_cherry_matches.id' AS relationship,
       COUNT(*) AS orphan_rows
FROM `phone_cherry_messages` c
LEFT JOIN `phone_cherry_matches` p ON p.`id` = c.`match_id`
WHERE c.`match_id` IS NOT NULL AND p.`id` IS NULL
UNION ALL
SELECT 'phone_documents.folder_id -> phone_document_folders.id' AS relationship,
       COUNT(*) AS orphan_rows
FROM `phone_documents` c
LEFT JOIN `phone_document_folders` p ON p.`id` = c.`folder_id`
WHERE c.`folder_id` IS NOT NULL AND p.`id` IS NULL
UNION ALL
SELECT 'phone_group_invites.group_id -> phone_groups.id' AS relationship,
       COUNT(*) AS orphan_rows
FROM `phone_group_invites` c
LEFT JOIN `phone_groups` p ON p.`id` = c.`group_id`
WHERE c.`group_id` IS NOT NULL AND p.`id` IS NULL
UNION ALL
SELECT 'phone_message_group_members.group_id -> phone_message_groups.id' AS relationship,
       COUNT(*) AS orphan_rows
FROM `phone_message_group_members` c
LEFT JOIN `phone_message_groups` p ON p.`id` = c.`group_id`
WHERE c.`group_id` IS NOT NULL AND p.`id` IS NULL
UNION ALL
SELECT 'phone_photo_album_items.album_id -> phone_photo_albums.id' AS relationship,
       COUNT(*) AS orphan_rows
FROM `phone_photo_album_items` c
LEFT JOIN `phone_photo_albums` p ON p.`id` = c.`album_id`
WHERE c.`album_id` IS NOT NULL AND p.`id` IS NULL
UNION ALL
SELECT 'phone_photo_album_items.photo_id -> phone_photos.id' AS relationship,
       COUNT(*) AS orphan_rows
FROM `phone_photo_album_items` c
LEFT JOIN `phone_photos` p ON p.`id` = c.`photo_id`
WHERE c.`photo_id` IS NOT NULL AND p.`id` IS NULL
UNION ALL
SELECT 'phone_photogram_comment_likes.comment_id -> phone_photogram_comments.id' AS relationship,
       COUNT(*) AS orphan_rows
FROM `phone_photogram_comment_likes` c
LEFT JOIN `phone_photogram_comments` p ON p.`id` = c.`comment_id`
WHERE c.`comment_id` IS NOT NULL AND p.`id` IS NULL
UNION ALL
SELECT 'phone_photogram_comments.post_id -> phone_photogram_posts.id' AS relationship,
       COUNT(*) AS orphan_rows
FROM `phone_photogram_comments` c
LEFT JOIN `phone_photogram_posts` p ON p.`id` = c.`post_id`
WHERE c.`post_id` IS NOT NULL AND p.`id` IS NULL
UNION ALL
SELECT 'phone_photogram_likes.post_id -> phone_photogram_posts.id' AS relationship,
       COUNT(*) AS orphan_rows
FROM `phone_photogram_likes` c
LEFT JOIN `phone_photogram_posts` p ON p.`id` = c.`post_id`
WHERE c.`post_id` IS NOT NULL AND p.`id` IS NULL
UNION ALL
SELECT 'phone_photogram_notifications.post_id -> phone_photogram_posts.id' AS relationship,
       COUNT(*) AS orphan_rows
FROM `phone_photogram_notifications` c
LEFT JOIN `phone_photogram_posts` p ON p.`id` = c.`post_id`
WHERE c.`post_id` IS NOT NULL AND p.`id` IS NULL
UNION ALL
SELECT 'phone_photogram_saves.post_id -> phone_photogram_posts.id' AS relationship,
       COUNT(*) AS orphan_rows
FROM `phone_photogram_saves` c
LEFT JOIN `phone_photogram_posts` p ON p.`id` = c.`post_id`
WHERE c.`post_id` IS NOT NULL AND p.`id` IS NULL
UNION ALL
SELECT 'phone_review_helpful.review_id -> phone_review_reviews.id' AS relationship,
       COUNT(*) AS orphan_rows
FROM `phone_review_helpful` c
LEFT JOIN `phone_review_reviews` p ON p.`id` = c.`review_id`
WHERE c.`review_id` IS NOT NULL AND p.`id` IS NULL
UNION ALL
SELECT 'phone_streak_likes.post_id -> phone_streak_posts.id' AS relationship,
       COUNT(*) AS orphan_rows
FROM `phone_streak_likes` c
LEFT JOIN `phone_streak_posts` p ON p.`id` = c.`post_id`
WHERE c.`post_id` IS NOT NULL AND p.`id` IS NULL
UNION ALL
SELECT 'phone_vibez_comment_likes.comment_id -> phone_vibez_comments.id' AS relationship,
       COUNT(*) AS orphan_rows
FROM `phone_vibez_comment_likes` c
LEFT JOIN `phone_vibez_comments` p ON p.`id` = c.`comment_id`
WHERE c.`comment_id` IS NOT NULL AND p.`id` IS NULL
UNION ALL
SELECT 'phone_vibez_comments.post_id -> phone_vibez_posts.id' AS relationship,
       COUNT(*) AS orphan_rows
FROM `phone_vibez_comments` c
LEFT JOIN `phone_vibez_posts` p ON p.`id` = c.`post_id`
WHERE c.`post_id` IS NOT NULL AND p.`id` IS NULL
UNION ALL
SELECT 'phone_vibez_likes.post_id -> phone_vibez_posts.id' AS relationship,
       COUNT(*) AS orphan_rows
FROM `phone_vibez_likes` c
LEFT JOIN `phone_vibez_posts` p ON p.`id` = c.`post_id`
WHERE c.`post_id` IS NOT NULL AND p.`id` IS NULL
UNION ALL
SELECT 'phone_vibez_notifications.post_id -> phone_vibez_posts.id' AS relationship,
       COUNT(*) AS orphan_rows
FROM `phone_vibez_notifications` c
LEFT JOIN `phone_vibez_posts` p ON p.`id` = c.`post_id`
WHERE c.`post_id` IS NOT NULL AND p.`id` IS NULL
UNION ALL
SELECT 'phone_vibez_saves.post_id -> phone_vibez_posts.id' AS relationship,
       COUNT(*) AS orphan_rows
FROM `phone_vibez_saves` c
LEFT JOIN `phone_vibez_posts` p ON p.`id` = c.`post_id`
WHERE c.`post_id` IS NOT NULL AND p.`id` IS NULL
ORDER BY orphan_rows DESC, relationship;


-- ---------------------------------------------------------------------------
-- Type / collation compatibility. A FOREIGN KEY needs the child and parent columns to share a
-- data type and, for strings, the SAME collation. Any row where match_ok = 0 must be aligned
-- first (util.ensureCollation exists because MariaDB defaults can drift from utf8mb4_unicode_ci).
-- Portable form: UNION ALL rather than VALUES, which differs between MySQL 8 and MariaDB.
-- ---------------------------------------------------------------------------

SELECT CONCAT(p.child_tbl, '.', p.child_col, ' -> ', p.parent_tbl, '.', p.parent_col) AS relationship,
       cc.COLUMN_TYPE AS child_type, cc.COLLATION_NAME AS child_collation,
       pc.COLUMN_TYPE AS parent_type, pc.COLLATION_NAME AS parent_collation,
       (cc.COLUMN_TYPE = pc.COLUMN_TYPE
        AND COALESCE(cc.COLLATION_NAME, '') = COALESCE(pc.COLLATION_NAME, '')) AS match_ok
FROM (
  -- child_tbl / child_col / parent_tbl / parent_col
  SELECT 'darkchat_bans' AS child_tbl, 'room_id' AS child_col, 'darkchat_rooms' AS parent_tbl, 'id' AS parent_col
  UNION ALL SELECT 'darkchat_members', 'room_id', 'darkchat_rooms', 'id'
  UNION ALL SELECT 'darkchat_messages', 'room_id', 'darkchat_rooms', 'id'
  UNION ALL SELECT 'darkchat_reactions', 'message_id', 'darkchat_messages', 'id'
  UNION ALL SELECT 'phone_app_sessions', 'account_id', 'phone_app_accounts', 'id'
  UNION ALL SELECT 'phone_birdy_likes', 'post_id', 'phone_birdy_posts', 'id'
  UNION ALL SELECT 'phone_birdy_notifications', 'post_id', 'phone_birdy_posts', 'id'
  UNION ALL SELECT 'phone_birdy_reposts', 'post_id', 'phone_birdy_posts', 'id'
  UNION ALL SELECT 'phone_cherry_messages', 'match_id', 'phone_cherry_matches', 'id'
  UNION ALL SELECT 'phone_documents', 'folder_id', 'phone_document_folders', 'id'
  UNION ALL SELECT 'phone_group_invites', 'group_id', 'phone_groups', 'id'
  UNION ALL SELECT 'phone_message_group_members', 'group_id', 'phone_message_groups', 'id'
  UNION ALL SELECT 'phone_photo_album_items', 'album_id', 'phone_photo_albums', 'id'
  UNION ALL SELECT 'phone_photo_album_items', 'photo_id', 'phone_photos', 'id'
  UNION ALL SELECT 'phone_photogram_comment_likes', 'comment_id', 'phone_photogram_comments', 'id'
  UNION ALL SELECT 'phone_photogram_comments', 'post_id', 'phone_photogram_posts', 'id'
  UNION ALL SELECT 'phone_photogram_likes', 'post_id', 'phone_photogram_posts', 'id'
  UNION ALL SELECT 'phone_photogram_notifications', 'post_id', 'phone_photogram_posts', 'id'
  UNION ALL SELECT 'phone_photogram_saves', 'post_id', 'phone_photogram_posts', 'id'
  UNION ALL SELECT 'phone_review_helpful', 'review_id', 'phone_review_reviews', 'id'
  UNION ALL SELECT 'phone_streak_likes', 'post_id', 'phone_streak_posts', 'id'
  UNION ALL SELECT 'phone_vibez_comment_likes', 'comment_id', 'phone_vibez_comments', 'id'
  UNION ALL SELECT 'phone_vibez_comments', 'post_id', 'phone_vibez_posts', 'id'
  UNION ALL SELECT 'phone_vibez_likes', 'post_id', 'phone_vibez_posts', 'id'
  UNION ALL SELECT 'phone_vibez_notifications', 'post_id', 'phone_vibez_posts', 'id'
  UNION ALL SELECT 'phone_vibez_saves', 'post_id', 'phone_vibez_posts', 'id'
) AS p
LEFT JOIN information_schema.COLUMNS cc ON cc.TABLE_SCHEMA = DATABASE() AND cc.TABLE_NAME = p.child_tbl  AND cc.COLUMN_NAME = p.child_col
LEFT JOIN information_schema.COLUMNS pc ON pc.TABLE_SCHEMA = DATABASE() AND pc.TABLE_NAME = p.parent_tbl AND pc.COLUMN_NAME = p.parent_col
ORDER BY match_ok ASC, relationship;
