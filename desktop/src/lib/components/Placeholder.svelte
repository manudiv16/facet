<script lang="ts">
	export let title: string;
	export let description: string;
</script>

<section class="placeholder">
	<h1>{title}</h1>
	<p>{description}</p>
</section>

<style>
	.placeholder {
		max-width: 640px;
	}

	h1 {
		margin: 0 0 0.5rem;
		font-size: 1.5rem;
	}

	p {
		color: var(--text-muted);
		font-size: 0.95rem;
	}
</style>
