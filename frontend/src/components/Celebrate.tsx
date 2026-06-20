import { useEffect } from 'react';

interface Props {
  show: boolean;
  title: string;
  sub: string;
  onDone: () => void;
}

export default function Celebrate({ show, title, sub, onDone }: Props) {
  useEffect(() => {
    if (!show) return;
    const t = setTimeout(onDone, 2800);
    return () => clearTimeout(t);
  }, [show, onDone]);

  if (!show) return null;

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/70 cursor-pointer"
      style={{ animation: 'fade 0.25s ease' }}
      onClick={onDone}
    >
      <div className="text-center bg-slate-800 border border-indigo-500 rounded-2xl px-10 py-8 shadow-[0_0_60px_rgba(99,102,241,0.35)]">
        <div className="flex gap-2 justify-center text-3xl mb-3">
          {Array.from({ length: 7 }).map((_, i) => (
            <span
              key={i}
              className="text-yellow-400 inline-block"
              style={{ animation: 'hop 0.7s ease infinite', animationDelay: `${i * 0.09}s` }}
            >
              ◎
            </span>
          ))}
        </div>
        <h3 className="text-lg font-bold text-slate-100 mb-1">{title}</h3>
        <p className="text-slate-400 text-sm">{sub}</p>
      </div>
    </div>
  );
}
