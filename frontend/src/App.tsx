import { Toaster } from "@/components/ui/toaster";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { AuthProvider } from "@/auth/AuthContext";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Routes, Route } from "react-router-dom";
import { RequireAuth } from "@/components/RequireAuth";
import Dashboard from "@/components/Dashboard";
import Login from "@/pages/Login";
import Signup from "@/pages/Signup";
import Onboarding from "@/pages/Onboarding";
import Share from "@/pages/Share";
import Schedule from "@/pages/Schedule";
import AuthAction from "@/pages/AuthAction";
import VerificationPending from "@/pages/VerificationPending";
import ResetPassword from "@/pages/ResetPassword";
import ChooseUsername from "@/pages/ChooseUsername";
import NotFound from "@/pages/NotFound";

const queryClient = new QueryClient();

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
            <Route path="/onboarding" element={
              <RequireAuth>
                <Onboarding />
              </RequireAuth>
            } />
            <Route path="/app" element={
              <RequireAuth>
                <Dashboard />
              </RequireAuth>
            } />
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
