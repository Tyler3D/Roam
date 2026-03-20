import { Toaster } from "@/components/ui/toaster";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { AuthProvider } from "@/auth";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Routes, Route } from "react-router-dom";
import { RequireAuth } from "@/components/RequireAuth";
import AppLayout from "@/components/AppLayout";
import IdeasView from "@/pages/IdeasView";
import DraftsView from "@/pages/DraftsView";
import PlansView from "@/components/PlansView";
import InboxView from "@/components/InboxView";
import IdeaMap from "@/pages/IdeaMap";
import ProfilePage from "@/pages/ProfilePage";
import Login from "@/pages/Login";
import Signup from "@/pages/Signup";
import Onboarding from "@/pages/Onboarding";
import Share from "@/pages/Share";
import Schedule from "@/pages/Schedule";
import AuthAction from "@/pages/AuthAction";
import VerificationPending from "@/pages/VerificationPending";
import ResetPassword from "@/pages/ResetPassword";
import ChooseUsername from "@/pages/ChooseUsername";
import IdeaOverview from "@/pages/IdeaOverview";
import PlanOverview from "@/pages/PlanOverview";
import NotFound from "@/pages/NotFound";

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 30 * 1000, // 30s
      retry: (failureCount, error) => {
        const status = (error as { status?: number })?.status;
        if (status === 404) return false;
        if (status && status >= 400 && status < 500) return false;
        return failureCount < 2;
      },
    },
  },
});

const App = () => (
  <QueryClientProvider client={queryClient}>
    <AuthProvider>
      <TooltipProvider>
        <Toaster />
        <Sonner />
        <BrowserRouter>
          <Routes>
            <Route path="/" element={<Login />} />
            <Route path="/login" element={<Login />} />
            <Route path="/signup" element={<Signup />} />
            <Route path="/reset-password" element={<ResetPassword />} />
            <Route path="/verification" element={<VerificationPending />} />
            <Route path="/auth/action" element={<AuthAction />} />
            <Route path="/choose-username" element={<ChooseUsername />} />
            <Route
              path="/onboarding"
              element={
                <RequireAuth>
                  <Onboarding />
                </RequireAuth>
              }
            />
            <Route
              path="/app"
              element={
                <RequireAuth>
                  <AppLayout />
                </RequireAuth>
              }
            >
              <Route index element={<IdeasView />} />
              <Route path="drafts" element={<DraftsView />} />
              <Route path="plans" element={<PlansView />} />
              <Route path="map" element={<IdeaMap />} />
              <Route path="notifications" element={<InboxView />} />
            </Route>
            <Route
              path="/profile"
              element={
                <RequireAuth>
                  <ProfilePage />
                </RequireAuth>
              }
            />
            <Route
              path="/ideas/:ideaId"
              element={
                <RequireAuth>
                  <IdeaOverview />
                </RequireAuth>
              }
            />
            <Route
              path="/plans/:planId"
              element={
                <RequireAuth>
                  <PlanOverview />
                </RequireAuth>
              }
            />
            <Route path="/share/schedule" element={<Schedule />} />
            <Route path="/share/:shareCode" element={<Share />} />
            <Route path="*" element={<NotFound />} />
          </Routes>
        </BrowserRouter>
      </TooltipProvider>
    </AuthProvider>
  </QueryClientProvider>
);

export default App;
