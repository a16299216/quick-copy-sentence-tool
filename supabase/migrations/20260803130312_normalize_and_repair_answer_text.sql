do $cleanup$
declare
  v_admin uuid;
begin
  select id into v_admin
  from public.profiles
  where username = 'admin' and deleted_at is null
  limit 1;

  if v_admin is null then
    raise exception '找不到用于记录文字清理的管理员账号';
  end if;

  insert into public.answer_history(answer_item_id, version, snapshot_json, action, actor_id)
  select id, version, to_jsonb(answer_items), '简体字形与文字清理前备份', v_admin
  from public.answer_items
  where deleted_at is null
    and answer_code = any(array[
      '1-1-1','1-1-2','1-1-3','1-1-4',
      '2-4-1','2-4-2','2-4-3','2-4-4',
      '2-5-1','2-5-2','2-5-3','2-5-4',
      '3-1-1','3-1-2','3-1-3','3-1-4','3-2',
      '4-2-1','4-2-2','4-2-3','4-2-4',
      '4-3-1','4-3-2','4-3-3','4-3-4',
      '5-1-1','5-1-3','5-1-4','5-1-5','6-1'
    ]);

  update public.answer_items
  set answer_text = E'您好，请查看图解步骤：\n至“赚钱”页面获取推广链接，即可邀请好友。',
      version = version + 1, updated_by = v_admin, updated_at = now()
  where deleted_at is null and answer_code = any(array['1-1-1','1-1-2','1-1-3','1-1-4']);

  update public.answer_items
  set answer_text = E'您好，该好友通过页签包注册，因此无法计入下级。\n请让新好友按照图示复制推广链接至浏览器，通过网页版注册。',
      version = version + 1, updated_by = v_admin, updated_at = now()
  where deleted_at is null and answer_code = any(array['2-4-1','2-4-2','2-4-3','2-4-4']);

  update public.answer_items
  set answer_text = E'您好，您的好友没有通过您的推广链接注册，因此不会计入您的下级人数。\n请让新好友按照图示复制推广链接至浏览器，通过网页版注册。',
      version = version + 1, updated_by = v_admin, updated_at = now()
  where deleted_at is null and answer_code = any(array['2-5-1','2-5-2','2-5-3','2-5-4']);

  update public.answer_items
  set answer_text = E'您好，请查看图解步骤：\n至“赚钱”页面点击“好友任务”，即可领取彩金。',
      version = version + 1, updated_by = v_admin, updated_at = now()
  where deleted_at is null and answer_code = any(array['3-1-1','3-1-2','3-1-3','3-1-4']);

  update public.answer_items
  set answer_text = E'您好，请退出页面并清除缓存，同时结束所有 APP 进程。\n等待3—5分钟后重新进入“好友任务”尝试领取。',
      version = version + 1, updated_by = v_admin, updated_at = now()
  where deleted_at is null and answer_code = '3-2';

  update public.answer_items
  set answer_text = E'您好，受邀人尚未完成姓名、手机号及支付宝绑定。\n您可以查看图片了解正确的活动邀请条件。',
      version = version + 1, updated_by = v_admin, updated_at = now()
  where deleted_at is null and answer_code = '4-2-1';

  update public.answer_items
  set answer_text = E'您好，受邀人尚未完成姓名、手机号及银行卡绑定。\n您可以查看图片了解正确的活动邀请条件。',
      version = version + 1, updated_by = v_admin, updated_at = now()
  where deleted_at is null and answer_code = any(array['4-2-2','4-2-3','4-2-4']);

  update public.answer_items
  set answer_text = E'您好，您的好友并非本周注册，新一轮活动已经开始。\n您可以查看图片了解正确的活动参与条件。',
      version = version + 1, updated_by = v_admin, updated_at = now()
  where deleted_at is null and answer_code = any(array['4-3-1','4-3-2','4-3-3','4-3-4']);

  update public.answer_items
  set answer_text = E'您好，好友投注奖励无需申请，将于每周一24:00前派发。\n请按照图示至“赚钱”页面领取。',
      version = version + 1, updated_by = v_admin, updated_at = now()
  where deleted_at is null and answer_code = any(array['5-1-1','5-1-3','5-1-4','5-1-5']);

  update public.answer_items
  set answer_text = E'您好，由于您的账号存在异常，系统将不予审核派发佣金。\n此为系统自动检测结果，待系统检测正常后会自动恢复。',
      version = version + 1, updated_by = v_admin, updated_at = now()
  where deleted_at is null and answer_code = '6-1';
end;
$cleanup$;
