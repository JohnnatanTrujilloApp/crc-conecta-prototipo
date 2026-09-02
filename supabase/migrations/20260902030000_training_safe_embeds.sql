-- Formación 2.0: proveedores externos permitidos para contenido incrustado.
alter table public.lesson_resources add column if not exists embed_provider text;
alter table public.lesson_resources drop constraint if exists lesson_resources_embed_provider_check;
alter table public.lesson_resources add constraint lesson_resources_embed_provider_check check(
 embed_provider is null or embed_provider in ('PREZI','VIMEO','GOOGLE_SLIDES','POWERPOINT','GENIALLY','CANVA')
);
comment on column public.lesson_resources.embed_provider is 'Proveedor validado por CRC Conecta; nunca almacena HTML iframe arbitrario.';
