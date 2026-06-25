<script lang="ts">
  const { children, multiple, disabled, onDrop, onEnter, onLeave } = $props();

  let isOver: boolean = false;
  let input: HTMLInputElement;

  const handleEnter = () => {
    isOver = true;
    if (onEnter) {
      onEnter();
    }
  };

  const handleLeave = () => {
    isOver = false;
    if (onLeave) {
      onLeave();
    }
  };

  const handleDrop = (e: DragEvent) => {
    e.preventDefault();

    if (!e?.dataTransfer?.items || disabled) {
      return;
    }
    const items = Array.from(e.dataTransfer.files);
    onDrop(items);
    isOver = false;
  };

  const handleDragOver = (e: Event) => {
    e.preventDefault();
  };

  const handleChange = (e: Event) => {
    e.preventDefault();
    const files: FileList = <FileList>(<HTMLInputElement>e.target).files;
    onDrop(Array.from(files));
  };

  const onClick = () => {
    input.click();
  };

  const onKeyDown = (e: KeyboardEvent) => {
    if (e.key === 'Enter') {
      input.click();
    }
  };
</script>

<div
  id="zone"
  ondrop={handleDrop}
  ondragover={handleDragOver}
  ondragenter={handleEnter}
  ondragleave={handleLeave}
  onclick={onClick}
  onkeydown={onKeyDown}
  tabIndex={0}
>
  {@render children()}
</div>
<input
  id="hidden-input"
  type="file"
  onchange={handleChange}
  bind:this={input}
  {multiple}
  {disabled}
/>

<style>
  #zone {
    width: 100%;
    height: 100%;
  }
  #hidden-input {
    display: none;
  }
</style>
