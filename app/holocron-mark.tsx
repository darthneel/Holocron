type HolocronMarkProps = {
  className?: string;
};

export function HolocronMark({className = "holocron-mark"}: HolocronMarkProps) {
  return (
    <svg className={className} viewBox="0 0 64 64" aria-hidden="true">
      <path d="M46 8A24 24 0 0 0 46 56" />
      <path d="M46 18A14 14 0 0 0 46 46" />
      <path d="M46 27A5 5 0 0 0 46 37" />
      <circle cx="53" cy="32" r="4.5" />
    </svg>
  );
}
