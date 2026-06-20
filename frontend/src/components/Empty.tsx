interface Props {
  icon?: string;
  title: string;
  hint?: string;
  cta?: string;
  onCta?: () => void;
}

export default function Empty({ icon = '○', title, hint, cta, onCta }: Props) {
  return (
    <div className="text-center py-10 px-5 border border-dashed border-slate-700 rounded-xl">
      <div className="text-4xl opacity-60 mb-3">{icon}</div>
      <h4 className="text-slate-200 font-semibold mb-1">{title}</h4>
      {hint && <p className="text-slate-400 text-sm mb-3 max-w-xs mx-auto">{hint}</p>}
      {cta && onCta && (
        <button onClick={onCta}
          className="text-sm text-indigo-400 hover:text-indigo-300 border border-indigo-700 rounded px-3 py-1.5 transition-colors">
          {cta}
        </button>
      )}
    </div>
  );
}
