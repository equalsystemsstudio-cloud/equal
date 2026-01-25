-- RPC: Get local posts by country (is_public only)
create or replace function public.get_local_posts(
  country text,
  limit_count int,
  offset_count int
) returns setof posts as $$
  select p.*
  from public.posts p
  where p.is_public = true
    and coalesce(p.location, '') ilike '%' || country || '%'
  order by p.created_at desc
  offset offset_count
  limit limit_count;
$$ language sql stable;

-- RPC: Get niche posts by tags using hashtags array overlap
create or replace function public.get_niche_posts_by_tags(
  tags text[],
  limit_count int,
  offset_count int
) returns setof posts as $$
  select p.*
  from public.posts p
  where p.is_public = true
    and p.hashtags && tags
  order by p.created_at desc
  offset offset_count
  limit limit_count;
$$ language sql stable;

-- Optional helper: compute top tags from likes (not used directly client-side here)
create or replace function public.get_user_top_hashtags(
  uid uuid,
  top_n int
) returns table(tag text, freq int) as $$
  with liked as (
    select l.post_id
    from public.likes l
    where l.user_id = uid
    order by l.created_at desc
    limit 500
  ),
  tag_list as (
    select unnest(p.hashtags) as tag
    from public.posts p
    join liked l on l.post_id = p.id
    where array_length(p.hashtags, 1) is not null
  )
  select tag, count(*) as freq
  from tag_list
  group by tag
  order by freq desc
  limit top_n;
$$ language sql stable;

