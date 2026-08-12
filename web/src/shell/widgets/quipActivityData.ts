import type { BirdyNotification } from '@/apps/birdy/data';

export interface QuipActivityEntry {
    id:      string;
    kind:    BirdyNotification['kind'];
    actor:   string;
    action:  string;
    preview?: string;
}

export function projectQuipActivity(item: BirdyNotification): QuipActivityEntry {
    if (item.kind === 'reply') {
        return {
            id:      item.id,
            kind:    item.kind,
            actor:   item.post.author.name,
            action:  'replied to your post',
            preview: item.post.body,
        };
    }

    if (item.kind === 'follow') {
        return {
            id:     item.id,
            kind:   item.kind,
            actor:  item.user.name,
            action: 'is now following you',
        };
    }

    return {
        id:      item.id,
        kind:    item.kind,
        actor:   item.user.name,
        action:  item.text,
        preview: item.post?.body,
    };
}
