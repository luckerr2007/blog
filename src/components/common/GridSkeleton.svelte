<!-- 加载骨架：标签行 + 筛选胶囊 + 卡片网格 + 分页 -->
<div class="border-b border-(--line-divider) mb-3" aria-hidden="true">
  <div class="flex min-w-max space-x-8">
    {#each [1, 2, 3, 4] as _}
      <div class="skeleton h-10 w-20 rounded"></div>
    {/each}
  </div>
</div>
<!-- 筛选骨架 -->
<div class="flex flex-wrap gap-1.5 mb-4" aria-hidden="true">
  {#each [1, 2, 3, 4] as _}
    <div class="skeleton h-7 w-16 rounded-full"></div>
  {/each}
</div>
<!-- 卡片网格骨架 -->
<div class="media-grid grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 gap-3" aria-hidden="true">
  {#each [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12] as _}
    <div class="rounded-xl overflow-hidden">
      <div class="skeleton aspect-2/3"></div>
    </div>
  {/each}
</div>
<!-- 分页骨架 -->
<div class="mt-6 flex items-center justify-center gap-3" aria-hidden="true">
  <div class="skeleton w-11 h-11 rounded-lg"></div>
  <div class="skeleton w-16 h-8 rounded"></div>
  <div class="skeleton w-11 h-11 rounded-lg"></div>
</div>
