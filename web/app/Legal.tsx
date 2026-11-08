import { AlphaBar, SiteFooter, SiteHeader } from "./Chrome";

// Platzhalter "[...]" orange hervorheben, damit nichts Unausgefülltes online geht.
export function V({ children }: { children: string }) {
  return children.startsWith("[") ? <mark className="todo">{children}</mark> : <>{children}</>;
}

export function LegalPage({
  title,
  subtitle,
  children,
}: {
  title: string;
  subtitle?: string;
  children: React.ReactNode;
}) {
  return (
    <>
      <AlphaBar />
      <SiteHeader home={false} />
      <main className="wrap legal">
        <h1>{title}</h1>
        {subtitle && (
          <p className="legal-sub" lang="de">
            {subtitle}
          </p>
        )}
        {children}
      </main>
      <SiteFooter />
    </>
  );
}
