<script lang="ts">
  export let href: string = "/";
  export let logoUrl: string | undefined = undefined;
</script>

<a {href} class="grid place-content-center rounded pl-2 pr-2">
  {#if logoUrl}
    <img src={logoUrl} alt="logo" class="h-7" />
  {:else}
    <img
      src="/img/matny-black.png"
      alt="Matny"
      class="h-7 w-auto dark:hidden"
    />
    <img
      src="/img/matny-white.png"
      alt="Matny"
      class="hidden h-7 w-auto dark:block"
    />
  {/if}
</a>
