import { Link } from "react-router-dom";
import { Button } from "@/components/ui/button";

export default function Marketing() {
  return (
    <div className="min-h-screen bg-background">
      <header className="max-w-5xl mx-auto px-6 py-10 flex items-center justify-between">
        <div className="text-xl font-semibold">Roam Alpha</div>
        <div className="flex items-center gap-3">
          <Button variant="ghost" asChild>
            <Link to="/login">Sign In</Link>
          </Button>
          <Button asChild>
            <Link to="/signup">Get Started</Link>
          </Button>
        </div>
      </header>

      <main className="max-w-5xl mx-auto px-6 pb-20">
        <section className="grid gap-10 md:grid-cols-2 items-center">
          <div className="space-y-5">
            <p className="text-sm font-medium text-primary">
              Save better date ideas
            </p>
            <h1 className="text-4xl md:text-5xl font-display font-semibold">
              Turn moments into memorable date plans.
            </h1>
            <p className="text-muted-foreground text-lg">
              Capture date ideas from anywhere, organize them by location, and
              share with your favorite person. No more lost screenshots.
            </p>
            <div className="flex items-center gap-3">
              <Button asChild>
                <Link to="/signup">Create an account</Link>
              </Button>
              <Button variant="outline" asChild>
                <Link to="/login">I already have one</Link>
              </Button>
            </div>
          </div>
          <div className="rounded-3xl border border-border/60 bg-card p-6 shadow-sm space-y-4">
            <div className="rounded-2xl bg-muted/50 p-4">
              <p className="text-sm text-muted-foreground">Tonight's pick</p>
              <p className="text-lg font-medium">Rooftop bar at sunset</p>
            </div>
            <div className="rounded-2xl bg-muted/50 p-4">
              <p className="text-sm text-muted-foreground">Plan ahead</p>
              <p className="text-lg font-medium">Pottery class for two</p>
            </div>
            <div className="rounded-2xl bg-muted/50 p-4">
              <p className="text-sm text-muted-foreground">Rediscover</p>
              <p className="text-lg font-medium">Hidden garden café</p>
            </div>
          </div>
        </section>
      </main>
    </div>
  );
}
