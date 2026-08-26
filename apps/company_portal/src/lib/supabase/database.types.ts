export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.17"
  }
  public: {
    Tables: {
      application_events: {
        Row: {
          actor_id: string | null
          actor_type: Database["public"]["Enums"]["actor_type"]
          application_id: string
          event_type: Database["public"]["Enums"]["application_event_type"]
          from_stage_id: string | null
          from_state: Database["public"]["Enums"]["application_state"] | null
          id: number
          metadata: Json
          occurred_at: string
          reason: string | null
          to_stage_id: string | null
          to_state: Database["public"]["Enums"]["application_state"] | null
        }
        Insert: {
          actor_id?: string | null
          actor_type: Database["public"]["Enums"]["actor_type"]
          application_id: string
          event_type: Database["public"]["Enums"]["application_event_type"]
          from_stage_id?: string | null
          from_state?: Database["public"]["Enums"]["application_state"] | null
          id?: number
          metadata?: Json
          occurred_at?: string
          reason?: string | null
          to_stage_id?: string | null
          to_state?: Database["public"]["Enums"]["application_state"] | null
        }
        Update: {
          actor_id?: string | null
          actor_type?: Database["public"]["Enums"]["actor_type"]
          application_id?: string
          event_type?: Database["public"]["Enums"]["application_event_type"]
          from_stage_id?: string | null
          from_state?: Database["public"]["Enums"]["application_state"] | null
          id?: number
          metadata?: Json
          occurred_at?: string
          reason?: string | null
          to_stage_id?: string | null
          to_state?: Database["public"]["Enums"]["application_state"] | null
        }
        Relationships: [
          {
            foreignKeyName: "application_events_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "application_events_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "applications"
            referencedColumns: ["id"]
          },
        ]
      }
      application_notes: {
        Row: {
          application_id: string
          author_id: string | null
          body: string
          company_id: string
          created_at: string
          id: string
        }
        Insert: {
          application_id: string
          author_id?: string | null
          body: string
          company_id: string
          created_at?: string
          id?: string
        }
        Update: {
          application_id?: string
          author_id?: string | null
          body?: string
          company_id?: string
          created_at?: string
          id?: string
        }
        Relationships: [
          {
            foreignKeyName: "application_notes_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "applications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "application_notes_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "application_notes_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
        ]
      }
      applications: {
        Row: {
          answers: Json
          applied_at: string
          applied_via: string
          closed_at: string | null
          company_id: string
          cover_note: string | null
          first_viewed_at: string | null
          id: string
          identity_snapshot: Json
          is_archived: boolean | null
          job_id: string
          last_activity_at: string
          match_score: number | null
          person_id: string
          rejected_by: string | null
          rejection_reason: string | null
          resume_document_id: string | null
          stage_id: string | null
          state: Database["public"]["Enums"]["application_state"]
          withdrawal_reason: string | null
          work_identity_id: string
        }
        Insert: {
          answers?: Json
          applied_at?: string
          applied_via?: string
          closed_at?: string | null
          company_id: string
          cover_note?: string | null
          first_viewed_at?: string | null
          id?: string
          identity_snapshot?: Json
          is_archived?: boolean | null
          job_id: string
          last_activity_at?: string
          match_score?: number | null
          person_id: string
          rejected_by?: string | null
          rejection_reason?: string | null
          resume_document_id?: string | null
          stage_id?: string | null
          state?: Database["public"]["Enums"]["application_state"]
          withdrawal_reason?: string | null
          work_identity_id: string
        }
        Update: {
          answers?: Json
          applied_at?: string
          applied_via?: string
          closed_at?: string | null
          company_id?: string
          cover_note?: string | null
          first_viewed_at?: string | null
          id?: string
          identity_snapshot?: Json
          is_archived?: boolean | null
          job_id?: string
          last_activity_at?: string
          match_score?: number | null
          person_id?: string
          rejected_by?: string | null
          rejection_reason?: string | null
          resume_document_id?: string | null
          stage_id?: string | null
          state?: Database["public"]["Enums"]["application_state"]
          withdrawal_reason?: string | null
          work_identity_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "applications_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "applications_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "applications_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "applications_rejected_by_fkey"
            columns: ["rejected_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "applications_resume_document_id_fkey"
            columns: ["resume_document_id"]
            isOneToOne: false
            referencedRelation: "documents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "applications_stage_id_fkey"
            columns: ["stage_id"]
            isOneToOne: false
            referencedRelation: "job_stages"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "applications_work_identity_id_fkey"
            columns: ["work_identity_id"]
            isOneToOne: false
            referencedRelation: "work_identities"
            referencedColumns: ["id"]
          },
        ]
      }
      assessments: {
        Row: {
          application_id: string
          completed_at: string | null
          created_at: string
          due_at: string | null
          external_url: string | null
          id: string
          job_id: string
          kind: string
          max_score: number | null
          name: string
          provider: string | null
          result: Json
          score: number | null
          sent_at: string | null
        }
        Insert: {
          application_id: string
          completed_at?: string | null
          created_at?: string
          due_at?: string | null
          external_url?: string | null
          id?: string
          job_id: string
          kind?: string
          max_score?: number | null
          name: string
          provider?: string | null
          result?: Json
          score?: number | null
          sent_at?: string | null
        }
        Update: {
          application_id?: string
          completed_at?: string | null
          created_at?: string
          due_at?: string | null
          external_url?: string | null
          id?: string
          job_id?: string
          kind?: string
          max_score?: number | null
          name?: string
          provider?: string | null
          result?: Json
          score?: number | null
          sent_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "assessments_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "applications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assessments_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
        ]
      }
      audit_log: {
        Row: {
          action: string
          actor_id: string | null
          actor_type: Database["public"]["Enums"]["actor_type"]
          company_id: string | null
          id: number
          ip_hash: string | null
          metadata: Json
          occurred_at: string
          subject_id: string | null
          subject_type: string
          user_agent: string | null
        }
        Insert: {
          action: string
          actor_id?: string | null
          actor_type: Database["public"]["Enums"]["actor_type"]
          company_id?: string | null
          id?: number
          ip_hash?: string | null
          metadata?: Json
          occurred_at?: string
          subject_id?: string | null
          subject_type: string
          user_agent?: string | null
        }
        Update: {
          action?: string
          actor_id?: string | null
          actor_type?: Database["public"]["Enums"]["actor_type"]
          company_id?: string | null
          id?: number
          ip_hash?: string | null
          metadata?: Json
          occurred_at?: string
          subject_id?: string | null
          subject_type?: string
          user_agent?: string | null
        }
        Relationships: []
      }
      automated_decision_log: {
        Row: {
          company_id: string | null
          decision_kind: string
          engine_version: string
          human_reviewed: boolean
          id: number
          job_id: string | null
          occurred_at: string
          outcome: Json
          person_id: string | null
          review_requested_at: string | null
          reviewed_at: string | null
        }
        Insert: {
          company_id?: string | null
          decision_kind: string
          engine_version: string
          human_reviewed?: boolean
          id?: number
          job_id?: string | null
          occurred_at?: string
          outcome: Json
          person_id?: string | null
          review_requested_at?: string | null
          reviewed_at?: string | null
        }
        Update: {
          company_id?: string | null
          decision_kind?: string
          engine_version?: string
          human_reviewed?: boolean
          id?: number
          job_id?: string | null
          occurred_at?: string
          outcome?: Json
          person_id?: string | null
          review_requested_at?: string | null
          reviewed_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "automated_decision_log_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "automated_decision_log_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "automated_decision_log_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      blocks: {
        Row: {
          created_at: string
          person_id: string
          reason: string | null
          target_id: string
          target_type: string
        }
        Insert: {
          created_at?: string
          person_id: string
          reason?: string | null
          target_id: string
          target_type: string
        }
        Update: {
          created_at?: string
          person_id?: string
          reason?: string | null
          target_id?: string
          target_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "blocks_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      candidate_invitations: {
        Row: {
          company_id: string
          id: string
          job_id: string
          message: string | null
          person_id: string
          responded_at: string | null
          response: string | null
          sent_at: string
          sent_by: string | null
          work_identity_id: string | null
        }
        Insert: {
          company_id: string
          id?: string
          job_id: string
          message?: string | null
          person_id: string
          responded_at?: string | null
          response?: string | null
          sent_at?: string
          sent_by?: string | null
          work_identity_id?: string | null
        }
        Update: {
          company_id?: string
          id?: string
          job_id?: string
          message?: string | null
          person_id?: string
          responded_at?: string | null
          response?: string | null
          sent_at?: string
          sent_by?: string | null
          work_identity_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "candidate_invitations_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "candidate_invitations_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "candidate_invitations_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "candidate_invitations_sent_by_fkey"
            columns: ["sent_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "candidate_invitations_work_identity_id_fkey"
            columns: ["work_identity_id"]
            isOneToOne: false
            referencedRelation: "work_identities"
            referencedColumns: ["id"]
          },
        ]
      }
      career_goals: {
        Row: {
          created_at: string
          goal_text: string | null
          id: string
          person_id: string
          priority: number
          profession_id: string | null
          target_countries: string[]
          target_currency: string | null
          target_pay_amount: number | null
          target_pay_period: Database["public"]["Enums"]["pay_period"] | null
          work_identity_id: string
        }
        Insert: {
          created_at?: string
          goal_text?: string | null
          id?: string
          person_id: string
          priority?: number
          profession_id?: string | null
          target_countries?: string[]
          target_currency?: string | null
          target_pay_amount?: number | null
          target_pay_period?: Database["public"]["Enums"]["pay_period"] | null
          work_identity_id: string
        }
        Update: {
          created_at?: string
          goal_text?: string | null
          id?: string
          person_id?: string
          priority?: number
          profession_id?: string | null
          target_countries?: string[]
          target_currency?: string | null
          target_pay_amount?: number | null
          target_pay_period?: Database["public"]["Enums"]["pay_period"] | null
          work_identity_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "career_goals_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "career_goals_profession_id_fkey"
            columns: ["profession_id"]
            isOneToOne: false
            referencedRelation: "professions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "career_goals_work_identity_id_fkey"
            columns: ["work_identity_id"]
            isOneToOne: false
            referencedRelation: "work_identities"
            referencedColumns: ["id"]
          },
        ]
      }
      companies: {
        Row: {
          about: string | null
          country_code: string | null
          cover_url: string | null
          created_at: string
          created_by: string | null
          culture: Json
          deleted_at: string | null
          display_name: string
          founded_year: number | null
          hq_location_id: string | null
          id: string
          industry_id: string | null
          is_verified: boolean
          legal_name: string | null
          logo_url: string | null
          media: Json
          median_response_hours: number | null
          registration_number: string | null
          response_rate_pct: number | null
          size_band: Database["public"]["Enums"]["company_size_band"] | null
          slug: string
          stats_computed_at: string | null
          tax_id: string | null
          total_hires: number
          updated_at: string
          verification_method:
            | Database["public"]["Enums"]["verification_method"]
            | null
          verified_at: string | null
          website: string | null
        }
        Insert: {
          about?: string | null
          country_code?: string | null
          cover_url?: string | null
          created_at?: string
          created_by?: string | null
          culture?: Json
          deleted_at?: string | null
          display_name: string
          founded_year?: number | null
          hq_location_id?: string | null
          id?: string
          industry_id?: string | null
          is_verified?: boolean
          legal_name?: string | null
          logo_url?: string | null
          media?: Json
          median_response_hours?: number | null
          registration_number?: string | null
          response_rate_pct?: number | null
          size_band?: Database["public"]["Enums"]["company_size_band"] | null
          slug: string
          stats_computed_at?: string | null
          tax_id?: string | null
          total_hires?: number
          updated_at?: string
          verification_method?:
            | Database["public"]["Enums"]["verification_method"]
            | null
          verified_at?: string | null
          website?: string | null
        }
        Update: {
          about?: string | null
          country_code?: string | null
          cover_url?: string | null
          created_at?: string
          created_by?: string | null
          culture?: Json
          deleted_at?: string | null
          display_name?: string
          founded_year?: number | null
          hq_location_id?: string | null
          id?: string
          industry_id?: string | null
          is_verified?: boolean
          legal_name?: string | null
          logo_url?: string | null
          media?: Json
          median_response_hours?: number | null
          registration_number?: string | null
          response_rate_pct?: number | null
          size_band?: Database["public"]["Enums"]["company_size_band"] | null
          slug?: string
          stats_computed_at?: string | null
          tax_id?: string | null
          total_hires?: number
          updated_at?: string
          verification_method?:
            | Database["public"]["Enums"]["verification_method"]
            | null
          verified_at?: string | null
          website?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "companies_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "companies_hq_location_id_fkey"
            columns: ["hq_location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "companies_industry_id_fkey"
            columns: ["industry_id"]
            isOneToOne: false
            referencedRelation: "industries"
            referencedColumns: ["id"]
          },
        ]
      }
      company_entitlements: {
        Row: {
          active_job_slots: number
          ai_credits_monthly: number
          company_id: string
          outreach_quota_daily: number
          plan: string
          recruiter_seats: number
          talent_search_enabled: boolean
          talent_search_quota_monthly: number
          updated_at: string
          valid_until: string | null
        }
        Insert: {
          active_job_slots?: number
          ai_credits_monthly?: number
          company_id: string
          outreach_quota_daily?: number
          plan?: string
          recruiter_seats?: number
          talent_search_enabled?: boolean
          talent_search_quota_monthly?: number
          updated_at?: string
          valid_until?: string | null
        }
        Update: {
          active_job_slots?: number
          ai_credits_monthly?: number
          company_id?: string
          outreach_quota_daily?: number
          plan?: string
          recruiter_seats?: number
          talent_search_enabled?: boolean
          talent_search_quota_monthly?: number
          updated_at?: string
          valid_until?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "company_entitlements_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: true
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
        ]
      }
      company_invitations: {
        Row: {
          accepted_at: string | null
          company_id: string
          created_at: string
          email: string
          expires_at: string
          id: string
          invited_by: string | null
          role: Database["public"]["Enums"]["company_role"]
          token_hash: string
        }
        Insert: {
          accepted_at?: string | null
          company_id: string
          created_at?: string
          email: string
          expires_at: string
          id?: string
          invited_by?: string | null
          role: Database["public"]["Enums"]["company_role"]
          token_hash: string
        }
        Update: {
          accepted_at?: string | null
          company_id?: string
          created_at?: string
          email?: string
          expires_at?: string
          id?: string
          invited_by?: string | null
          role?: Database["public"]["Enums"]["company_role"]
          token_hash?: string
        }
        Relationships: [
          {
            foreignKeyName: "company_invitations_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "company_invitations_invited_by_fkey"
            columns: ["invited_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      company_locations: {
        Row: {
          address: string | null
          company_id: string
          created_at: string
          geo: unknown
          id: string
          is_hq: boolean
          location_id: string | null
          name: string | null
        }
        Insert: {
          address?: string | null
          company_id: string
          created_at?: string
          geo?: unknown
          id?: string
          is_hq?: boolean
          location_id?: string | null
          name?: string | null
        }
        Update: {
          address?: string | null
          company_id?: string
          created_at?: string
          geo?: unknown
          id?: string
          is_hq?: boolean
          location_id?: string | null
          name?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "company_locations_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "company_locations_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
        ]
      }
      company_members: {
        Row: {
          company_id: string
          department_id: string | null
          id: string
          invited_by: string | null
          is_active: boolean
          joined_at: string
          person_id: string
          role: Database["public"]["Enums"]["company_role"]
          title: string | null
        }
        Insert: {
          company_id: string
          department_id?: string | null
          id?: string
          invited_by?: string | null
          is_active?: boolean
          joined_at?: string
          person_id: string
          role: Database["public"]["Enums"]["company_role"]
          title?: string | null
        }
        Update: {
          company_id?: string
          department_id?: string | null
          id?: string
          invited_by?: string | null
          is_active?: boolean
          joined_at?: string
          person_id?: string
          role?: Database["public"]["Enums"]["company_role"]
          title?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "company_members_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "company_members_department_id_fkey"
            columns: ["department_id"]
            isOneToOne: false
            referencedRelation: "departments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "company_members_invited_by_fkey"
            columns: ["invited_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "company_members_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      conversations: {
        Row: {
          application_id: string | null
          company_archived: boolean
          company_id: string
          created_at: string
          id: string
          initiated_by: Database["public"]["Enums"]["actor_type"]
          job_id: string | null
          last_message_at: string | null
          person_archived: boolean
          person_id: string
          subject: string | null
        }
        Insert: {
          application_id?: string | null
          company_archived?: boolean
          company_id: string
          created_at?: string
          id?: string
          initiated_by?: Database["public"]["Enums"]["actor_type"]
          job_id?: string | null
          last_message_at?: string | null
          person_archived?: boolean
          person_id: string
          subject?: string | null
        }
        Update: {
          application_id?: string | null
          company_archived?: boolean
          company_id?: string
          created_at?: string
          id?: string
          initiated_by?: Database["public"]["Enums"]["actor_type"]
          job_id?: string | null
          last_message_at?: string | null
          person_archived?: boolean
          person_id?: string
          subject?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "conversations_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "applications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "conversations_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "conversations_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "conversations_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      country_policies: {
        Row: {
          age_criteria_permitted: boolean
          country_code: string
          created_at: string
          default_currency: string
          default_pay_period: Database["public"]["Enums"]["pay_period"]
          gender_criteria_permitted: boolean
          legal_basis_note: string | null
          name: string
          phone_auth_preferred: boolean
          required_documents: Database["public"]["Enums"]["document_type"][]
          salary_disclosure_required: boolean
          supported: boolean
        }
        Insert: {
          age_criteria_permitted?: boolean
          country_code: string
          created_at?: string
          default_currency: string
          default_pay_period?: Database["public"]["Enums"]["pay_period"]
          gender_criteria_permitted?: boolean
          legal_basis_note?: string | null
          name: string
          phone_auth_preferred?: boolean
          required_documents?: Database["public"]["Enums"]["document_type"][]
          salary_disclosure_required?: boolean
          supported?: boolean
        }
        Update: {
          age_criteria_permitted?: boolean
          country_code?: string
          created_at?: string
          default_currency?: string
          default_pay_period?: Database["public"]["Enums"]["pay_period"]
          gender_criteria_permitted?: boolean
          legal_basis_note?: string | null
          name?: string
          phone_auth_preferred?: boolean
          required_documents?: Database["public"]["Enums"]["document_type"][]
          salary_disclosure_required?: boolean
          supported?: boolean
        }
        Relationships: []
      }
      credential_types: {
        Row: {
          category_id: string | null
          id: string
          issuer: string
          name: string
          status: Database["public"]["Enums"]["taxonomy_status"]
          verify_url_tpl: string | null
        }
        Insert: {
          category_id?: string | null
          id?: string
          issuer: string
          name: string
          status?: Database["public"]["Enums"]["taxonomy_status"]
          verify_url_tpl?: string | null
        }
        Update: {
          category_id?: string | null
          id?: string
          issuer?: string
          name?: string
          status?: Database["public"]["Enums"]["taxonomy_status"]
          verify_url_tpl?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "credential_types_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "job_categories"
            referencedColumns: ["id"]
          },
        ]
      }
      departments: {
        Row: {
          company_id: string
          created_at: string
          id: string
          name: string
          parent_id: string | null
        }
        Insert: {
          company_id: string
          created_at?: string
          id?: string
          name: string
          parent_id?: string | null
        }
        Update: {
          company_id?: string
          created_at?: string
          id?: string
          name?: string
          parent_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "departments_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "departments_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "departments"
            referencedColumns: ["id"]
          },
        ]
      }
      document_shares: {
        Row: {
          application_id: string | null
          company_id: string | null
          document_id: string
          expires_at: string | null
          granted_at: string
          id: string
          person_id: string
          revoked_at: string | null
        }
        Insert: {
          application_id?: string | null
          company_id?: string | null
          document_id: string
          expires_at?: string | null
          granted_at?: string
          id?: string
          person_id: string
          revoked_at?: string | null
        }
        Update: {
          application_id?: string | null
          company_id?: string | null
          document_id?: string
          expires_at?: string | null
          granted_at?: string
          id?: string
          person_id?: string
          revoked_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "document_shares_company_fk"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "document_shares_document_id_fkey"
            columns: ["document_id"]
            isOneToOne: false
            referencedRelation: "documents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "document_shares_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      documents: {
        Row: {
          created_at: string
          deleted_at: string | null
          expires_on: string | null
          id: string
          is_generated: boolean
          is_sensitive: boolean
          mime_type: string | null
          name: string
          person_id: string
          scan_status: string
          size_bytes: number | null
          storage_path: string
          type: Database["public"]["Enums"]["document_type"]
        }
        Insert: {
          created_at?: string
          deleted_at?: string | null
          expires_on?: string | null
          id?: string
          is_generated?: boolean
          is_sensitive?: boolean
          mime_type?: string | null
          name: string
          person_id: string
          scan_status?: string
          size_bytes?: number | null
          storage_path: string
          type: Database["public"]["Enums"]["document_type"]
        }
        Update: {
          created_at?: string
          deleted_at?: string | null
          expires_on?: string | null
          id?: string
          is_generated?: boolean
          is_sensitive?: boolean
          mime_type?: string | null
          name?: string
          person_id?: string
          scan_status?: string
          size_bytes?: number | null
          storage_path?: string
          type?: Database["public"]["Enums"]["document_type"]
        }
        Relationships: [
          {
            foreignKeyName: "documents_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      educations: {
        Row: {
          created_at: string
          ended_on: string | null
          field_of_study: string | null
          grade: string | null
          id: string
          institution_id: string | null
          institution_name: string
          is_ongoing: boolean
          is_verified: boolean
          level: Database["public"]["Enums"]["education_level"]
          person_id: string
          source: Database["public"]["Enums"]["source_type"]
          started_on: string | null
        }
        Insert: {
          created_at?: string
          ended_on?: string | null
          field_of_study?: string | null
          grade?: string | null
          id?: string
          institution_id?: string | null
          institution_name: string
          is_ongoing?: boolean
          is_verified?: boolean
          level: Database["public"]["Enums"]["education_level"]
          person_id: string
          source?: Database["public"]["Enums"]["source_type"]
          started_on?: string | null
        }
        Update: {
          created_at?: string
          ended_on?: string | null
          field_of_study?: string | null
          grade?: string | null
          id?: string
          institution_id?: string | null
          institution_name?: string
          is_ongoing?: boolean
          is_verified?: boolean
          level?: Database["public"]["Enums"]["education_level"]
          person_id?: string
          source?: Database["public"]["Enums"]["source_type"]
          started_on?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "educations_institution_id_fkey"
            columns: ["institution_id"]
            isOneToOne: false
            referencedRelation: "institutions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "educations_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      employments: {
        Row: {
          application_id: string | null
          company_id: string
          created_at: string
          department_id: string | null
          end_reason: string | null
          ended_on: string | null
          id: string
          is_omelo_hire: boolean
          job_id: string | null
          location_id: string | null
          offer_id: string | null
          person_id: string
          profession_id: string | null
          started_on: string
          status: Database["public"]["Enums"]["employment_status"]
          title: string
          updated_at: string
          work_type: Database["public"]["Enums"]["work_type"] | null
          workplace_type: Database["public"]["Enums"]["workplace_type"] | null
        }
        Insert: {
          application_id?: string | null
          company_id: string
          created_at?: string
          department_id?: string | null
          end_reason?: string | null
          ended_on?: string | null
          id?: string
          is_omelo_hire?: boolean
          job_id?: string | null
          location_id?: string | null
          offer_id?: string | null
          person_id: string
          profession_id?: string | null
          started_on: string
          status?: Database["public"]["Enums"]["employment_status"]
          title: string
          updated_at?: string
          work_type?: Database["public"]["Enums"]["work_type"] | null
          workplace_type?: Database["public"]["Enums"]["workplace_type"] | null
        }
        Update: {
          application_id?: string | null
          company_id?: string
          created_at?: string
          department_id?: string | null
          end_reason?: string | null
          ended_on?: string | null
          id?: string
          is_omelo_hire?: boolean
          job_id?: string | null
          location_id?: string | null
          offer_id?: string | null
          person_id?: string
          profession_id?: string | null
          started_on?: string
          status?: Database["public"]["Enums"]["employment_status"]
          title?: string
          updated_at?: string
          work_type?: Database["public"]["Enums"]["work_type"] | null
          workplace_type?: Database["public"]["Enums"]["workplace_type"] | null
        }
        Relationships: [
          {
            foreignKeyName: "employments_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "applications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employments_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employments_department_id_fkey"
            columns: ["department_id"]
            isOneToOne: false
            referencedRelation: "departments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employments_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employments_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employments_offer_id_fkey"
            columns: ["offer_id"]
            isOneToOne: false
            referencedRelation: "offers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employments_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employments_profession_id_fkey"
            columns: ["profession_id"]
            isOneToOne: false
            referencedRelation: "professions"
            referencedColumns: ["id"]
          },
        ]
      }
      experiences: {
        Row: {
          company_id: string | null
          created_at: string
          description: string | null
          employer_name: string
          ended_on: string | null
          id: string
          is_current: boolean
          is_informal: boolean
          is_self_employed: boolean
          is_verified: boolean
          location_id: string | null
          location_text: string | null
          months_duration: number | null
          pay_amount: number | null
          pay_currency: string | null
          pay_period: Database["public"]["Enums"]["pay_period"] | null
          person_id: string
          profession_id: string | null
          reason_for_leaving: string | null
          responsibilities: Json
          source: Database["public"]["Enums"]["source_type"]
          started_on: string | null
          title: string
          verified_employment_id: string | null
          work_identity_id: string | null
          work_type: Database["public"]["Enums"]["work_type"] | null
          workplace_type: Database["public"]["Enums"]["workplace_type"] | null
        }
        Insert: {
          company_id?: string | null
          created_at?: string
          description?: string | null
          employer_name: string
          ended_on?: string | null
          id?: string
          is_current?: boolean
          is_informal?: boolean
          is_self_employed?: boolean
          is_verified?: boolean
          location_id?: string | null
          location_text?: string | null
          months_duration?: number | null
          pay_amount?: number | null
          pay_currency?: string | null
          pay_period?: Database["public"]["Enums"]["pay_period"] | null
          person_id: string
          profession_id?: string | null
          reason_for_leaving?: string | null
          responsibilities?: Json
          source?: Database["public"]["Enums"]["source_type"]
          started_on?: string | null
          title: string
          verified_employment_id?: string | null
          work_identity_id?: string | null
          work_type?: Database["public"]["Enums"]["work_type"] | null
          workplace_type?: Database["public"]["Enums"]["workplace_type"] | null
        }
        Update: {
          company_id?: string | null
          created_at?: string
          description?: string | null
          employer_name?: string
          ended_on?: string | null
          id?: string
          is_current?: boolean
          is_informal?: boolean
          is_self_employed?: boolean
          is_verified?: boolean
          location_id?: string | null
          location_text?: string | null
          months_duration?: number | null
          pay_amount?: number | null
          pay_currency?: string | null
          pay_period?: Database["public"]["Enums"]["pay_period"] | null
          person_id?: string
          profession_id?: string | null
          reason_for_leaving?: string | null
          responsibilities?: Json
          source?: Database["public"]["Enums"]["source_type"]
          started_on?: string | null
          title?: string
          verified_employment_id?: string | null
          work_identity_id?: string | null
          work_type?: Database["public"]["Enums"]["work_type"] | null
          workplace_type?: Database["public"]["Enums"]["workplace_type"] | null
        }
        Relationships: [
          {
            foreignKeyName: "experiences_company_fk"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "experiences_employment_fk"
            columns: ["verified_employment_id"]
            isOneToOne: false
            referencedRelation: "employments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "experiences_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "experiences_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "experiences_profession_id_fkey"
            columns: ["profession_id"]
            isOneToOne: false
            referencedRelation: "professions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "experiences_work_identity_id_fkey"
            columns: ["work_identity_id"]
            isOneToOne: false
            referencedRelation: "work_identities"
            referencedColumns: ["id"]
          },
        ]
      }
      follows: {
        Row: {
          created_at: string
          person_id: string
          target_id: string
          target_type: string
        }
        Insert: {
          created_at?: string
          person_id: string
          target_id: string
          target_type: string
        }
        Update: {
          created_at?: string
          person_id?: string
          target_id?: string
          target_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "follows_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      fraud_signals: {
        Row: {
          detail: Json
          detected_at: string
          id: number
          severity: number
          signal: string
          subject_id: string
          subject_type: string
        }
        Insert: {
          detail?: Json
          detected_at?: string
          id?: number
          severity?: number
          signal: string
          subject_id: string
          subject_type: string
        }
        Update: {
          detail?: Json
          detected_at?: string
          id?: number
          severity?: number
          signal?: string
          subject_id?: string
          subject_type?: string
        }
        Relationships: []
      }
      hidden_jobs: {
        Row: {
          created_at: string
          job_id: string
          person_id: string
          reason: string | null
        }
        Insert: {
          created_at?: string
          job_id: string
          person_id: string
          reason?: string | null
        }
        Update: {
          created_at?: string
          job_id?: string
          person_id?: string
          reason?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "hidden_jobs_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hidden_jobs_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      industries: {
        Row: {
          id: string
          name: string
          parent_id: string | null
          slug: string
        }
        Insert: {
          id?: string
          name: string
          parent_id?: string | null
          slug: string
        }
        Update: {
          id?: string
          name?: string
          parent_id?: string | null
          slug?: string
        }
        Relationships: [
          {
            foreignKeyName: "industries_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "industries"
            referencedColumns: ["id"]
          },
        ]
      }
      ingestion_runs: {
        Row: {
          errors: Json
          finished_at: string | null
          id: string
          jobs_closed: number
          jobs_created: number
          jobs_seen: number
          jobs_updated: number
          source_id: string
          started_at: string
        }
        Insert: {
          errors?: Json
          finished_at?: string | null
          id?: string
          jobs_closed?: number
          jobs_created?: number
          jobs_seen?: number
          jobs_updated?: number
          source_id: string
          started_at?: string
        }
        Update: {
          errors?: Json
          finished_at?: string | null
          id?: string
          jobs_closed?: number
          jobs_created?: number
          jobs_seen?: number
          jobs_updated?: number
          source_id?: string
          started_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "ingestion_runs_source_id_fkey"
            columns: ["source_id"]
            isOneToOne: false
            referencedRelation: "job_sources"
            referencedColumns: ["id"]
          },
        ]
      }
      institutions: {
        Row: {
          country_code: string | null
          created_at: string
          id: string
          name: string
          status: Database["public"]["Enums"]["taxonomy_status"]
          website: string | null
        }
        Insert: {
          country_code?: string | null
          created_at?: string
          id?: string
          name: string
          status?: Database["public"]["Enums"]["taxonomy_status"]
          website?: string | null
        }
        Update: {
          country_code?: string | null
          created_at?: string
          id?: string
          name?: string
          status?: Database["public"]["Enums"]["taxonomy_status"]
          website?: string | null
        }
        Relationships: []
      }
      interview_interviewers: {
        Row: {
          interview_id: string
          is_lead: boolean
          person_id: string
        }
        Insert: {
          interview_id: string
          is_lead?: boolean
          person_id: string
        }
        Update: {
          interview_id?: string
          is_lead?: boolean
          person_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "interview_interviewers_interview_id_fkey"
            columns: ["interview_id"]
            isOneToOne: false
            referencedRelation: "interviews"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "interview_interviewers_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      interview_scorecards: {
        Row: {
          id: string
          interview_id: string
          interviewer_id: string
          notes: string | null
          overall_score: number | null
          recommendation:
            | Database["public"]["Enums"]["interview_recommendation"]
            | null
          scores: Json
          submitted_at: string
        }
        Insert: {
          id?: string
          interview_id: string
          interviewer_id: string
          notes?: string | null
          overall_score?: number | null
          recommendation?:
            | Database["public"]["Enums"]["interview_recommendation"]
            | null
          scores?: Json
          submitted_at?: string
        }
        Update: {
          id?: string
          interview_id?: string
          interviewer_id?: string
          notes?: string | null
          overall_score?: number | null
          recommendation?:
            | Database["public"]["Enums"]["interview_recommendation"]
            | null
          scores?: Json
          submitted_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "interview_scorecards_interview_id_fkey"
            columns: ["interview_id"]
            isOneToOne: false
            referencedRelation: "interviews"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "interview_scorecards_interviewer_id_fkey"
            columns: ["interviewer_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      interviews: {
        Row: {
          application_id: string
          cancel_reason: string | null
          cancelled_at: string | null
          candidate_confirmed_at: string | null
          company_id: string
          completed_at: string | null
          created_at: string
          created_by: string | null
          duration_minutes: number | null
          geo: unknown
          id: string
          instructions: string | null
          job_id: string
          location_text: string | null
          meeting_url: string | null
          person_id: string
          round: number
          scheduled_at: string | null
          status: Database["public"]["Enums"]["interview_status"]
          timezone: string | null
          type: Database["public"]["Enums"]["interview_type"]
        }
        Insert: {
          application_id: string
          cancel_reason?: string | null
          cancelled_at?: string | null
          candidate_confirmed_at?: string | null
          company_id: string
          completed_at?: string | null
          created_at?: string
          created_by?: string | null
          duration_minutes?: number | null
          geo?: unknown
          id?: string
          instructions?: string | null
          job_id: string
          location_text?: string | null
          meeting_url?: string | null
          person_id: string
          round?: number
          scheduled_at?: string | null
          status?: Database["public"]["Enums"]["interview_status"]
          timezone?: string | null
          type: Database["public"]["Enums"]["interview_type"]
        }
        Update: {
          application_id?: string
          cancel_reason?: string | null
          cancelled_at?: string | null
          candidate_confirmed_at?: string | null
          company_id?: string
          completed_at?: string | null
          created_at?: string
          created_by?: string | null
          duration_minutes?: number | null
          geo?: unknown
          id?: string
          instructions?: string | null
          job_id?: string
          location_text?: string | null
          meeting_url?: string | null
          person_id?: string
          round?: number
          scheduled_at?: string | null
          status?: Database["public"]["Enums"]["interview_status"]
          timezone?: string | null
          type?: Database["public"]["Enums"]["interview_type"]
        }
        Relationships: [
          {
            foreignKeyName: "interviews_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "applications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "interviews_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "interviews_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "interviews_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "interviews_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      job_attribute_requirements: {
        Row: {
          attribute_id: string
          job_id: string
          requirement_level: Database["public"]["Enums"]["requirement_level"]
          value_bool: boolean | null
          value_json: Json | null
          value_number_max: number | null
          value_number_min: number | null
          value_text: string | null
        }
        Insert: {
          attribute_id: string
          job_id: string
          requirement_level?: Database["public"]["Enums"]["requirement_level"]
          value_bool?: boolean | null
          value_json?: Json | null
          value_number_max?: number | null
          value_number_min?: number | null
          value_text?: string | null
        }
        Update: {
          attribute_id?: string
          job_id?: string
          requirement_level?: Database["public"]["Enums"]["requirement_level"]
          value_bool?: boolean | null
          value_json?: Json | null
          value_number_max?: number | null
          value_number_min?: number | null
          value_text?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "job_attribute_requirements_attribute_id_fkey"
            columns: ["attribute_id"]
            isOneToOne: false
            referencedRelation: "profile_attributes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "job_attribute_requirements_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
        ]
      }
      job_benefits: {
        Row: {
          benefit_type: Database["public"]["Enums"]["benefit_type"]
          detail: string | null
          job_id: string
        }
        Insert: {
          benefit_type: Database["public"]["Enums"]["benefit_type"]
          detail?: string | null
          job_id: string
        }
        Update: {
          benefit_type?: Database["public"]["Enums"]["benefit_type"]
          detail?: string | null
          job_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "job_benefits_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
        ]
      }
      job_categories: {
        Row: {
          created_at: string
          icon: string | null
          id: string
          name: string
          position: number
          slug: string
          status: Database["public"]["Enums"]["taxonomy_status"]
        }
        Insert: {
          created_at?: string
          icon?: string | null
          id?: string
          name: string
          position?: number
          slug: string
          status?: Database["public"]["Enums"]["taxonomy_status"]
        }
        Update: {
          created_at?: string
          icon?: string | null
          id?: string
          name?: string
          position?: number
          slug?: string
          status?: Database["public"]["Enums"]["taxonomy_status"]
        }
        Relationships: []
      }
      job_credentials: {
        Row: {
          credential_type_id: string
          job_id: string
          requirement_level: Database["public"]["Enums"]["requirement_level"]
        }
        Insert: {
          credential_type_id: string
          job_id: string
          requirement_level?: Database["public"]["Enums"]["requirement_level"]
        }
        Update: {
          credential_type_id?: string
          job_id?: string
          requirement_level?: Database["public"]["Enums"]["requirement_level"]
        }
        Relationships: [
          {
            foreignKeyName: "job_credentials_credential_type_id_fkey"
            columns: ["credential_type_id"]
            isOneToOne: false
            referencedRelation: "credential_types"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "job_credentials_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
        ]
      }
      job_documents_required: {
        Row: {
          document_type: Database["public"]["Enums"]["document_type"]
          is_required: boolean
          job_id: string
          request_at_stage: string
        }
        Insert: {
          document_type: Database["public"]["Enums"]["document_type"]
          is_required?: boolean
          job_id: string
          request_at_stage?: string
        }
        Update: {
          document_type?: Database["public"]["Enums"]["document_type"]
          is_required?: boolean
          job_id?: string
          request_at_stage?: string
        }
        Relationships: [
          {
            foreignKeyName: "job_documents_required_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
        ]
      }
      job_languages: {
        Row: {
          job_id: string
          language_code: string
          min_proficiency: Database["public"]["Enums"]["language_proficiency"]
          requirement_level: Database["public"]["Enums"]["requirement_level"]
        }
        Insert: {
          job_id: string
          language_code: string
          min_proficiency?: Database["public"]["Enums"]["language_proficiency"]
          requirement_level?: Database["public"]["Enums"]["requirement_level"]
        }
        Update: {
          job_id?: string
          language_code?: string
          min_proficiency?: Database["public"]["Enums"]["language_proficiency"]
          requirement_level?: Database["public"]["Enums"]["requirement_level"]
        }
        Relationships: [
          {
            foreignKeyName: "job_languages_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "job_languages_language_code_fkey"
            columns: ["language_code"]
            isOneToOne: false
            referencedRelation: "languages"
            referencedColumns: ["code"]
          },
        ]
      }
      job_legal_restrictions: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          created_at: string
          gender_requirement: string | null
          job_id: string
          legal_basis: string
          max_age: number | null
          min_age: number | null
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          created_at?: string
          gender_requirement?: string | null
          job_id: string
          legal_basis: string
          max_age?: number | null
          min_age?: number | null
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          created_at?: string
          gender_requirement?: string | null
          job_id?: string
          legal_basis?: string
          max_age?: number | null
          min_age?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "job_legal_restrictions_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "job_legal_restrictions_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: true
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
        ]
      }
      job_licenses: {
        Row: {
          job_id: string
          license_class: string | null
          license_type_id: string
          requirement_level: Database["public"]["Enums"]["requirement_level"]
        }
        Insert: {
          job_id: string
          license_class?: string | null
          license_type_id: string
          requirement_level?: Database["public"]["Enums"]["requirement_level"]
        }
        Update: {
          job_id?: string
          license_class?: string | null
          license_type_id?: string
          requirement_level?: Database["public"]["Enums"]["requirement_level"]
        }
        Relationships: [
          {
            foreignKeyName: "job_licenses_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "job_licenses_license_type_id_fkey"
            columns: ["license_type_id"]
            isOneToOne: false
            referencedRelation: "license_types"
            referencedColumns: ["id"]
          },
        ]
      }
      job_locations: {
        Row: {
          job_id: string
          location_id: string
        }
        Insert: {
          job_id: string
          location_id: string
        }
        Update: {
          job_id?: string
          location_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "job_locations_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "job_locations_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
        ]
      }
      job_questions: {
        Row: {
          answer_type: string
          id: string
          is_knockout: boolean
          is_required: boolean
          job_id: string
          knockout_expected: Json | null
          options: Json | null
          position: number
          prompt: string
        }
        Insert: {
          answer_type: string
          id?: string
          is_knockout?: boolean
          is_required?: boolean
          job_id: string
          knockout_expected?: Json | null
          options?: Json | null
          position: number
          prompt: string
        }
        Update: {
          answer_type?: string
          id?: string
          is_knockout?: boolean
          is_required?: boolean
          job_id?: string
          knockout_expected?: Json | null
          options?: Json | null
          position?: number
          prompt?: string
        }
        Relationships: [
          {
            foreignKeyName: "job_questions_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
        ]
      }
      job_skills: {
        Row: {
          job_id: string
          min_months: number | null
          requirement_level: Database["public"]["Enums"]["requirement_level"]
          skill_id: string
          weight: number
        }
        Insert: {
          job_id: string
          min_months?: number | null
          requirement_level?: Database["public"]["Enums"]["requirement_level"]
          skill_id: string
          weight?: number
        }
        Update: {
          job_id?: string
          min_months?: number | null
          requirement_level?: Database["public"]["Enums"]["requirement_level"]
          skill_id?: string
          weight?: number
        }
        Relationships: [
          {
            foreignKeyName: "job_skills_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "job_skills_skill_id_fkey"
            columns: ["skill_id"]
            isOneToOne: false
            referencedRelation: "skills"
            referencedColumns: ["id"]
          },
        ]
      }
      job_sources: {
        Row: {
          contract_ref: string | null
          created_at: string
          id: string
          is_active: boolean
          kind: string
          last_synced_at: string | null
          name: string
          terms_url: string | null
        }
        Insert: {
          contract_ref?: string | null
          created_at?: string
          id?: string
          is_active?: boolean
          kind: string
          last_synced_at?: string | null
          name: string
          terms_url?: string | null
        }
        Update: {
          contract_ref?: string | null
          created_at?: string
          id?: string
          is_active?: boolean
          kind?: string
          last_synced_at?: string | null
          name?: string
          terms_url?: string | null
        }
        Relationships: []
      }
      job_stages: {
        Row: {
          created_at: string
          id: string
          is_terminal: boolean
          job_id: string
          maps_to_state: Database["public"]["Enums"]["application_state"]
          name: string
          position: number
        }
        Insert: {
          created_at?: string
          id?: string
          is_terminal?: boolean
          job_id: string
          maps_to_state: Database["public"]["Enums"]["application_state"]
          name: string
          position: number
        }
        Update: {
          created_at?: string
          id?: string
          is_terminal?: boolean
          job_id?: string
          maps_to_state?: Database["public"]["Enums"]["application_state"]
          name?: string
          position?: number
        }
        Relationships: [
          {
            foreignKeyName: "job_stages_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
        ]
      }
      jobs: {
        Row: {
          accepts_no_experience: boolean
          accepts_non_residents: boolean | null
          applicant_count: number
          application_method: string
          category_id: string | null
          closed_at: string | null
          company_id: string
          company_location_id: string | null
          contact_phone: string | null
          content_language: string | null
          country_code: string | null
          created_at: string
          created_by: string | null
          department_id: string | null
          description: string | null
          duration_months: number | null
          education_negotiable: boolean
          expires_at: string | null
          external_apply_url: string | null
          external_id: string | null
          external_source_id: string | null
          geo: unknown
          hours_per_week: number | null
          id: string
          is_immediate_start: boolean
          job_embedding: string | null
          location_id: string | null
          location_text: string | null
          max_experience_months: number | null
          min_education: Database["public"]["Enums"]["education_level"] | null
          min_experience_months: number | null
          openings: number
          overtime_available: boolean | null
          own_tools_required: boolean | null
          own_vehicle_required: boolean | null
          pay_basis: Database["public"]["Enums"]["pay_basis"] | null
          pay_currency: string | null
          pay_disclosed: boolean | null
          pay_max: number | null
          pay_min: number | null
          pay_negotiable: boolean
          pay_period: Database["public"]["Enums"]["pay_period"] | null
          physical_requirements: Json
          profession_id: string | null
          profession_source: Database["public"]["Enums"]["source_type"] | null
          published_at: string | null
          quick_apply_enabled: boolean
          relocation_support: boolean
          requirements_text: Json
          requires_resume: boolean
          responsibilities: Json
          schedule_note: string | null
          shift_types: Database["public"]["Enums"]["shift_type"][]
          source: Database["public"]["Enums"]["source_type"]
          start_date: string | null
          status: Database["public"]["Enums"]["job_status"]
          title: string
          uniform_required: boolean | null
          updated_at: string
          view_count: number
          visa_sponsorship: boolean | null
          walk_in_details: string | null
          work_environment: string | null
          work_type: Database["public"]["Enums"]["work_type"]
          working_days: number | null
          workplace_type: Database["public"]["Enums"]["workplace_type"]
        }
        Insert: {
          accepts_no_experience?: boolean
          accepts_non_residents?: boolean | null
          applicant_count?: number
          application_method?: string
          category_id?: string | null
          closed_at?: string | null
          company_id: string
          company_location_id?: string | null
          contact_phone?: string | null
          content_language?: string | null
          country_code?: string | null
          created_at?: string
          created_by?: string | null
          department_id?: string | null
          description?: string | null
          duration_months?: number | null
          education_negotiable?: boolean
          expires_at?: string | null
          external_apply_url?: string | null
          external_id?: string | null
          external_source_id?: string | null
          geo?: unknown
          hours_per_week?: number | null
          id?: string
          is_immediate_start?: boolean
          job_embedding?: string | null
          location_id?: string | null
          location_text?: string | null
          max_experience_months?: number | null
          min_education?: Database["public"]["Enums"]["education_level"] | null
          min_experience_months?: number | null
          openings?: number
          overtime_available?: boolean | null
          own_tools_required?: boolean | null
          own_vehicle_required?: boolean | null
          pay_basis?: Database["public"]["Enums"]["pay_basis"] | null
          pay_currency?: string | null
          pay_disclosed?: boolean | null
          pay_max?: number | null
          pay_min?: number | null
          pay_negotiable?: boolean
          pay_period?: Database["public"]["Enums"]["pay_period"] | null
          physical_requirements?: Json
          profession_id?: string | null
          profession_source?: Database["public"]["Enums"]["source_type"] | null
          published_at?: string | null
          quick_apply_enabled?: boolean
          relocation_support?: boolean
          requirements_text?: Json
          requires_resume?: boolean
          responsibilities?: Json
          schedule_note?: string | null
          shift_types?: Database["public"]["Enums"]["shift_type"][]
          source?: Database["public"]["Enums"]["source_type"]
          start_date?: string | null
          status?: Database["public"]["Enums"]["job_status"]
          title: string
          uniform_required?: boolean | null
          updated_at?: string
          view_count?: number
          visa_sponsorship?: boolean | null
          walk_in_details?: string | null
          work_environment?: string | null
          work_type?: Database["public"]["Enums"]["work_type"]
          working_days?: number | null
          workplace_type?: Database["public"]["Enums"]["workplace_type"]
        }
        Update: {
          accepts_no_experience?: boolean
          accepts_non_residents?: boolean | null
          applicant_count?: number
          application_method?: string
          category_id?: string | null
          closed_at?: string | null
          company_id?: string
          company_location_id?: string | null
          contact_phone?: string | null
          content_language?: string | null
          country_code?: string | null
          created_at?: string
          created_by?: string | null
          department_id?: string | null
          description?: string | null
          duration_months?: number | null
          education_negotiable?: boolean
          expires_at?: string | null
          external_apply_url?: string | null
          external_id?: string | null
          external_source_id?: string | null
          geo?: unknown
          hours_per_week?: number | null
          id?: string
          is_immediate_start?: boolean
          job_embedding?: string | null
          location_id?: string | null
          location_text?: string | null
          max_experience_months?: number | null
          min_education?: Database["public"]["Enums"]["education_level"] | null
          min_experience_months?: number | null
          openings?: number
          overtime_available?: boolean | null
          own_tools_required?: boolean | null
          own_vehicle_required?: boolean | null
          pay_basis?: Database["public"]["Enums"]["pay_basis"] | null
          pay_currency?: string | null
          pay_disclosed?: boolean | null
          pay_max?: number | null
          pay_min?: number | null
          pay_negotiable?: boolean
          pay_period?: Database["public"]["Enums"]["pay_period"] | null
          physical_requirements?: Json
          profession_id?: string | null
          profession_source?: Database["public"]["Enums"]["source_type"] | null
          published_at?: string | null
          quick_apply_enabled?: boolean
          relocation_support?: boolean
          requirements_text?: Json
          requires_resume?: boolean
          responsibilities?: Json
          schedule_note?: string | null
          shift_types?: Database["public"]["Enums"]["shift_type"][]
          source?: Database["public"]["Enums"]["source_type"]
          start_date?: string | null
          status?: Database["public"]["Enums"]["job_status"]
          title?: string
          uniform_required?: boolean | null
          updated_at?: string
          view_count?: number
          visa_sponsorship?: boolean | null
          walk_in_details?: string | null
          work_environment?: string | null
          work_type?: Database["public"]["Enums"]["work_type"]
          working_days?: number | null
          workplace_type?: Database["public"]["Enums"]["workplace_type"]
        }
        Relationships: [
          {
            foreignKeyName: "jobs_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "job_categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "jobs_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "jobs_company_location_id_fkey"
            columns: ["company_location_id"]
            isOneToOne: false
            referencedRelation: "company_locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "jobs_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "jobs_department_id_fkey"
            columns: ["department_id"]
            isOneToOne: false
            referencedRelation: "departments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "jobs_external_source_fk"
            columns: ["external_source_id"]
            isOneToOne: false
            referencedRelation: "job_sources"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "jobs_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "jobs_profession_id_fkey"
            columns: ["profession_id"]
            isOneToOne: false
            referencedRelation: "professions"
            referencedColumns: ["id"]
          },
        ]
      }
      languages: {
        Row: {
          code: string
          name: string
          native_name: string | null
          rtl: boolean
        }
        Insert: {
          code: string
          name: string
          native_name?: string | null
          rtl?: boolean
        }
        Update: {
          code?: string
          name?: string
          native_name?: string | null
          rtl?: boolean
        }
        Relationships: []
      }
      license_types: {
        Row: {
          category_id: string | null
          class_options: string[]
          country_code: string | null
          created_at: string
          id: string
          issuing_body: string | null
          name: string
          renewable: boolean
          slug: string
          status: Database["public"]["Enums"]["taxonomy_status"]
          verify_url_tpl: string | null
        }
        Insert: {
          category_id?: string | null
          class_options?: string[]
          country_code?: string | null
          created_at?: string
          id?: string
          issuing_body?: string | null
          name: string
          renewable?: boolean
          slug: string
          status?: Database["public"]["Enums"]["taxonomy_status"]
          verify_url_tpl?: string | null
        }
        Update: {
          category_id?: string | null
          class_options?: string[]
          country_code?: string | null
          created_at?: string
          id?: string
          issuing_body?: string | null
          name?: string
          renewable?: boolean
          slug?: string
          status?: Database["public"]["Enums"]["taxonomy_status"]
          verify_url_tpl?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "license_types_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "job_categories"
            referencedColumns: ["id"]
          },
        ]
      }
      locations: {
        Row: {
          admin_code: string | null
          country_code: string | null
          created_at: string
          geo: unknown
          id: string
          kind: string
          latitude: number | null
          longitude: number | null
          name: string
          parent_id: string | null
          population: number | null
          status: Database["public"]["Enums"]["taxonomy_status"]
          timezone: string | null
        }
        Insert: {
          admin_code?: string | null
          country_code?: string | null
          created_at?: string
          geo?: unknown
          id?: string
          kind: string
          latitude?: number | null
          longitude?: number | null
          name: string
          parent_id?: string | null
          population?: number | null
          status?: Database["public"]["Enums"]["taxonomy_status"]
          timezone?: string | null
        }
        Update: {
          admin_code?: string | null
          country_code?: string | null
          created_at?: string
          geo?: unknown
          id?: string
          kind?: string
          latitude?: number | null
          longitude?: number | null
          name?: string
          parent_id?: string | null
          population?: number | null
          status?: Database["public"]["Enums"]["taxonomy_status"]
          timezone?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "locations_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
        ]
      }
      matches: {
        Row: {
          computed_at: string
          eligible: boolean
          engine_version: string
          feature_vector: Json
          gate_failures: string[]
          id: string
          job_id: string
          person_id: string
          score: number
          weight_profile_id: string | null
          work_identity_id: string
        }
        Insert: {
          computed_at?: string
          eligible?: boolean
          engine_version: string
          feature_vector: Json
          gate_failures?: string[]
          id?: string
          job_id: string
          person_id: string
          score: number
          weight_profile_id?: string | null
          work_identity_id: string
        }
        Update: {
          computed_at?: string
          eligible?: boolean
          engine_version?: string
          feature_vector?: Json
          gate_failures?: string[]
          id?: string
          job_id?: string
          person_id?: string
          score?: number
          weight_profile_id?: string | null
          work_identity_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "matches_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "matches_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "matches_weight_profile_id_fkey"
            columns: ["weight_profile_id"]
            isOneToOne: false
            referencedRelation: "weight_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "matches_work_identity_id_fkey"
            columns: ["work_identity_id"]
            isOneToOne: false
            referencedRelation: "work_identities"
            referencedColumns: ["id"]
          },
        ]
      }
      messages: {
        Row: {
          action_payload: Json | null
          action_type: string | null
          body: string | null
          conversation_id: string
          document_id: string | null
          id: number
          kind: Database["public"]["Enums"]["message_kind"]
          read_at: string | null
          sender_person_id: string | null
          sender_type: Database["public"]["Enums"]["actor_type"]
          sent_at: string
        }
        Insert: {
          action_payload?: Json | null
          action_type?: string | null
          body?: string | null
          conversation_id: string
          document_id?: string | null
          id?: number
          kind?: Database["public"]["Enums"]["message_kind"]
          read_at?: string | null
          sender_person_id?: string | null
          sender_type: Database["public"]["Enums"]["actor_type"]
          sent_at?: string
        }
        Update: {
          action_payload?: Json | null
          action_type?: string | null
          body?: string | null
          conversation_id?: string
          document_id?: string | null
          id?: number
          kind?: Database["public"]["Enums"]["message_kind"]
          read_at?: string | null
          sender_person_id?: string | null
          sender_type?: Database["public"]["Enums"]["actor_type"]
          sent_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "messages_conversation_id_fkey"
            columns: ["conversation_id"]
            isOneToOne: false
            referencedRelation: "conversations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "messages_document_id_fkey"
            columns: ["document_id"]
            isOneToOne: false
            referencedRelation: "documents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "messages_sender_person_id_fkey"
            columns: ["sender_person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      moderation_actions: {
        Row: {
          action: Database["public"]["Enums"]["moderation_action"]
          actor_id: string | null
          created_at: string
          expires_at: string | null
          id: string
          reason: string
          report_id: string | null
          reversed_at: string | null
          subject_id: string
          subject_type: string
        }
        Insert: {
          action: Database["public"]["Enums"]["moderation_action"]
          actor_id?: string | null
          created_at?: string
          expires_at?: string | null
          id?: string
          reason: string
          report_id?: string | null
          reversed_at?: string | null
          subject_id: string
          subject_type: string
        }
        Update: {
          action?: Database["public"]["Enums"]["moderation_action"]
          actor_id?: string | null
          created_at?: string
          expires_at?: string | null
          id?: string
          reason?: string
          report_id?: string | null
          reversed_at?: string | null
          subject_id?: string
          subject_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "moderation_actions_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "moderation_actions_report_id_fkey"
            columns: ["report_id"]
            isOneToOne: false
            referencedRelation: "reports"
            referencedColumns: ["id"]
          },
        ]
      }
      notification_preferences: {
        Row: {
          email_enabled: boolean
          muted_types: Database["public"]["Enums"]["notification_type"][]
          person_id: string
          push_enabled: boolean
          quiet_hours_end: number | null
          quiet_hours_start: number | null
          sms_enabled: boolean
          updated_at: string
          whatsapp_enabled: boolean
        }
        Insert: {
          email_enabled?: boolean
          muted_types?: Database["public"]["Enums"]["notification_type"][]
          person_id: string
          push_enabled?: boolean
          quiet_hours_end?: number | null
          quiet_hours_start?: number | null
          sms_enabled?: boolean
          updated_at?: string
          whatsapp_enabled?: boolean
        }
        Update: {
          email_enabled?: boolean
          muted_types?: Database["public"]["Enums"]["notification_type"][]
          person_id?: string
          push_enabled?: boolean
          quiet_hours_end?: number | null
          quiet_hours_start?: number | null
          sms_enabled?: boolean
          updated_at?: string
          whatsapp_enabled?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "notification_preferences_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: true
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      notifications: {
        Row: {
          body: string | null
          created_at: string
          deeplink: string | null
          entity_id: string | null
          entity_type: string | null
          id: number
          person_id: string
          read_at: string | null
          title: string
          type: Database["public"]["Enums"]["notification_type"]
        }
        Insert: {
          body?: string | null
          created_at?: string
          deeplink?: string | null
          entity_id?: string | null
          entity_type?: string | null
          id?: number
          person_id: string
          read_at?: string | null
          title: string
          type: Database["public"]["Enums"]["notification_type"]
        }
        Update: {
          body?: string | null
          created_at?: string
          deeplink?: string | null
          entity_id?: string | null
          entity_type?: string | null
          id?: number
          person_id?: string
          read_at?: string | null
          title?: string
          type?: Database["public"]["Enums"]["notification_type"]
        }
        Relationships: [
          {
            foreignKeyName: "notifications_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      offers: {
        Row: {
          application_id: string
          benefits: Json
          company_id: string
          conditions: string | null
          contract_document_id: string | null
          created_at: string
          created_by: string | null
          decline_reason: string | null
          expires_at: string | null
          hours_per_week: number | null
          id: string
          job_id: string
          location_text: string | null
          pay_amount: number | null
          pay_basis: Database["public"]["Enums"]["pay_basis"] | null
          pay_currency: string | null
          pay_period: Database["public"]["Enums"]["pay_period"] | null
          person_id: string
          responded_at: string | null
          sent_at: string | null
          shift_types: Database["public"]["Enums"]["shift_type"][]
          start_date: string | null
          status: Database["public"]["Enums"]["offer_status"]
          title: string
          updated_at: string
          viewed_at: string | null
          work_type: Database["public"]["Enums"]["work_type"] | null
          workplace_type: Database["public"]["Enums"]["workplace_type"] | null
        }
        Insert: {
          application_id: string
          benefits?: Json
          company_id: string
          conditions?: string | null
          contract_document_id?: string | null
          created_at?: string
          created_by?: string | null
          decline_reason?: string | null
          expires_at?: string | null
          hours_per_week?: number | null
          id?: string
          job_id: string
          location_text?: string | null
          pay_amount?: number | null
          pay_basis?: Database["public"]["Enums"]["pay_basis"] | null
          pay_currency?: string | null
          pay_period?: Database["public"]["Enums"]["pay_period"] | null
          person_id: string
          responded_at?: string | null
          sent_at?: string | null
          shift_types?: Database["public"]["Enums"]["shift_type"][]
          start_date?: string | null
          status?: Database["public"]["Enums"]["offer_status"]
          title: string
          updated_at?: string
          viewed_at?: string | null
          work_type?: Database["public"]["Enums"]["work_type"] | null
          workplace_type?: Database["public"]["Enums"]["workplace_type"] | null
        }
        Update: {
          application_id?: string
          benefits?: Json
          company_id?: string
          conditions?: string | null
          contract_document_id?: string | null
          created_at?: string
          created_by?: string | null
          decline_reason?: string | null
          expires_at?: string | null
          hours_per_week?: number | null
          id?: string
          job_id?: string
          location_text?: string | null
          pay_amount?: number | null
          pay_basis?: Database["public"]["Enums"]["pay_basis"] | null
          pay_currency?: string | null
          pay_period?: Database["public"]["Enums"]["pay_period"] | null
          person_id?: string
          responded_at?: string | null
          sent_at?: string | null
          shift_types?: Database["public"]["Enums"]["shift_type"][]
          start_date?: string | null
          status?: Database["public"]["Enums"]["offer_status"]
          title?: string
          updated_at?: string
          viewed_at?: string | null
          work_type?: Database["public"]["Enums"]["work_type"] | null
          workplace_type?: Database["public"]["Enums"]["workplace_type"] | null
        }
        Relationships: [
          {
            foreignKeyName: "offers_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "applications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "offers_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "offers_contract_document_id_fkey"
            columns: ["contract_document_id"]
            isOneToOne: false
            referencedRelation: "documents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "offers_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "offers_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "offers_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      person_attributes: {
        Row: {
          attribute_id: string
          created_at: string
          id: string
          person_id: string
          source: Database["public"]["Enums"]["source_type"]
          value_bool: boolean | null
          value_date: string | null
          value_json: Json | null
          value_number: number | null
          value_text: string | null
          work_identity_id: string
        }
        Insert: {
          attribute_id: string
          created_at?: string
          id?: string
          person_id: string
          source?: Database["public"]["Enums"]["source_type"]
          value_bool?: boolean | null
          value_date?: string | null
          value_json?: Json | null
          value_number?: number | null
          value_text?: string | null
          work_identity_id: string
        }
        Update: {
          attribute_id?: string
          created_at?: string
          id?: string
          person_id?: string
          source?: Database["public"]["Enums"]["source_type"]
          value_bool?: boolean | null
          value_date?: string | null
          value_json?: Json | null
          value_number?: number | null
          value_text?: string | null
          work_identity_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "person_attributes_attribute_id_fkey"
            columns: ["attribute_id"]
            isOneToOne: false
            referencedRelation: "profile_attributes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "person_attributes_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "person_attributes_work_identity_id_fkey"
            columns: ["work_identity_id"]
            isOneToOne: false
            referencedRelation: "work_identities"
            referencedColumns: ["id"]
          },
        ]
      }
      person_credentials: {
        Row: {
          created_at: string
          credential_number: string | null
          credential_type_id: string | null
          document_id: string | null
          expires_on: string | null
          id: string
          is_verified: boolean
          issued_on: string | null
          issuer: string | null
          name: string
          person_id: string
          verification_url: string | null
        }
        Insert: {
          created_at?: string
          credential_number?: string | null
          credential_type_id?: string | null
          document_id?: string | null
          expires_on?: string | null
          id?: string
          is_verified?: boolean
          issued_on?: string | null
          issuer?: string | null
          name: string
          person_id: string
          verification_url?: string | null
        }
        Update: {
          created_at?: string
          credential_number?: string | null
          credential_type_id?: string | null
          document_id?: string | null
          expires_on?: string | null
          id?: string
          is_verified?: boolean
          issued_on?: string | null
          issuer?: string | null
          name?: string
          person_id?: string
          verification_url?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "person_credentials_credential_type_id_fkey"
            columns: ["credential_type_id"]
            isOneToOne: false
            referencedRelation: "credential_types"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "person_credentials_document_fk"
            columns: ["document_id"]
            isOneToOne: false
            referencedRelation: "documents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "person_credentials_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      person_languages: {
        Row: {
          can_read: boolean | null
          can_write: boolean | null
          language_code: string
          person_id: string
          proficiency: Database["public"]["Enums"]["language_proficiency"]
        }
        Insert: {
          can_read?: boolean | null
          can_write?: boolean | null
          language_code: string
          person_id: string
          proficiency: Database["public"]["Enums"]["language_proficiency"]
        }
        Update: {
          can_read?: boolean | null
          can_write?: boolean | null
          language_code?: string
          person_id?: string
          proficiency?: Database["public"]["Enums"]["language_proficiency"]
        }
        Relationships: [
          {
            foreignKeyName: "person_languages_language_code_fkey"
            columns: ["language_code"]
            isOneToOne: false
            referencedRelation: "languages"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "person_languages_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      person_licenses: {
        Row: {
          country_code: string | null
          created_at: string
          document_id: string | null
          expires_on: string | null
          id: string
          is_verified: boolean
          issued_on: string | null
          issuing_body: string | null
          license_class: string | null
          license_number: string | null
          license_type_id: string | null
          name: string
          person_id: string
          verification_status: Database["public"]["Enums"]["verification_status"]
        }
        Insert: {
          country_code?: string | null
          created_at?: string
          document_id?: string | null
          expires_on?: string | null
          id?: string
          is_verified?: boolean
          issued_on?: string | null
          issuing_body?: string | null
          license_class?: string | null
          license_number?: string | null
          license_type_id?: string | null
          name: string
          person_id: string
          verification_status?: Database["public"]["Enums"]["verification_status"]
        }
        Update: {
          country_code?: string | null
          created_at?: string
          document_id?: string | null
          expires_on?: string | null
          id?: string
          is_verified?: boolean
          issued_on?: string | null
          issuing_body?: string | null
          license_class?: string | null
          license_number?: string | null
          license_type_id?: string | null
          name?: string
          person_id?: string
          verification_status?: Database["public"]["Enums"]["verification_status"]
        }
        Relationships: [
          {
            foreignKeyName: "person_licenses_document_fk"
            columns: ["document_id"]
            isOneToOne: false
            referencedRelation: "documents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "person_licenses_license_type_id_fkey"
            columns: ["license_type_id"]
            isOneToOne: false
            referencedRelation: "license_types"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "person_licenses_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      person_location_preferences: {
        Row: {
          country_code: string | null
          created_at: string
          id: string
          kind: string
          location_id: string | null
          person_id: string
          priority: number
          radius_km: number | null
          work_identity_id: string
        }
        Insert: {
          country_code?: string | null
          created_at?: string
          id?: string
          kind: string
          location_id?: string | null
          person_id: string
          priority?: number
          radius_km?: number | null
          work_identity_id: string
        }
        Update: {
          country_code?: string | null
          created_at?: string
          id?: string
          kind?: string
          location_id?: string | null
          person_id?: string
          priority?: number
          radius_km?: number | null
          work_identity_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "person_location_preferences_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "person_location_preferences_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "person_location_preferences_work_identity_id_fkey"
            columns: ["work_identity_id"]
            isOneToOne: false
            referencedRelation: "work_identities"
            referencedColumns: ["id"]
          },
        ]
      }
      person_professions: {
        Row: {
          created_at: string
          months_experience: number | null
          person_id: string
          priority: number
          profession_id: string
          relationship: string
          work_identity_id: string
        }
        Insert: {
          created_at?: string
          months_experience?: number | null
          person_id: string
          priority?: number
          profession_id: string
          relationship: string
          work_identity_id: string
        }
        Update: {
          created_at?: string
          months_experience?: number | null
          person_id?: string
          priority?: number
          profession_id?: string
          relationship?: string
          work_identity_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "person_professions_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "person_professions_profession_id_fkey"
            columns: ["profession_id"]
            isOneToOne: false
            referencedRelation: "professions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "person_professions_work_identity_id_fkey"
            columns: ["work_identity_id"]
            isOneToOne: false
            referencedRelation: "work_identities"
            referencedColumns: ["id"]
          },
        ]
      }
      person_references: {
        Row: {
          company_name: string | null
          created_at: string
          email: string | null
          id: string
          is_verified: boolean
          name: string
          person_id: string
          phone: string | null
          relationship: string | null
        }
        Insert: {
          company_name?: string | null
          created_at?: string
          email?: string | null
          id?: string
          is_verified?: boolean
          name: string
          person_id: string
          phone?: string | null
          relationship?: string | null
        }
        Update: {
          company_name?: string | null
          created_at?: string
          email?: string | null
          id?: string
          is_verified?: boolean
          name?: string
          person_id?: string
          phone?: string | null
          relationship?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "person_references_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      person_skills: {
        Row: {
          created_at: string
          evidence_refs: Json
          evidence_type: Database["public"]["Enums"]["evidence_type"]
          id: string
          is_verified: boolean
          last_used_on: string | null
          months_used: number | null
          person_id: string
          proficiency: Database["public"]["Enums"]["proficiency_level"] | null
          skill_id: string
          source: Database["public"]["Enums"]["source_type"]
          work_identity_id: string | null
        }
        Insert: {
          created_at?: string
          evidence_refs?: Json
          evidence_type?: Database["public"]["Enums"]["evidence_type"]
          id?: string
          is_verified?: boolean
          last_used_on?: string | null
          months_used?: number | null
          person_id: string
          proficiency?: Database["public"]["Enums"]["proficiency_level"] | null
          skill_id: string
          source?: Database["public"]["Enums"]["source_type"]
          work_identity_id?: string | null
        }
        Update: {
          created_at?: string
          evidence_refs?: Json
          evidence_type?: Database["public"]["Enums"]["evidence_type"]
          id?: string
          is_verified?: boolean
          last_used_on?: string | null
          months_used?: number | null
          person_id?: string
          proficiency?: Database["public"]["Enums"]["proficiency_level"] | null
          skill_id?: string
          source?: Database["public"]["Enums"]["source_type"]
          work_identity_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "person_skills_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "person_skills_skill_id_fkey"
            columns: ["skill_id"]
            isOneToOne: false
            referencedRelation: "skills"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "person_skills_work_identity_id_fkey"
            columns: ["work_identity_id"]
            isOneToOne: false
            referencedRelation: "work_identities"
            referencedColumns: ["id"]
          },
        ]
      }
      person_work_preferences: {
        Row: {
          availability: Database["public"]["Enums"]["availability_window"]
          available_from: string | null
          current_pay_amount: number | null
          current_pay_period: Database["public"]["Enums"]["pay_period"] | null
          expected_pay_amount: number | null
          expected_pay_period: Database["public"]["Enums"]["pay_period"] | null
          max_weekly_hours: number | null
          min_outreach_pay_amount: number | null
          min_outreach_pay_period:
            | Database["public"]["Enums"]["pay_period"]
            | null
          minimum_pay_amount: number | null
          minimum_pay_period: Database["public"]["Enums"]["pay_period"] | null
          needs_accommodation: boolean
          needs_transport: boolean
          notice_period_days: number | null
          pay_basis: Database["public"]["Enums"]["pay_basis"] | null
          pay_currency: string | null
          person_id: string
          seeking: boolean
          shift_types: Database["public"]["Enums"]["shift_type"][]
          updated_at: string
          willing_to_relocate: boolean
          willing_to_travel: boolean
          work_identity_id: string
          work_types: Database["public"]["Enums"]["work_type"][]
          workplace_types: Database["public"]["Enums"]["workplace_type"][]
        }
        Insert: {
          availability?: Database["public"]["Enums"]["availability_window"]
          available_from?: string | null
          current_pay_amount?: number | null
          current_pay_period?: Database["public"]["Enums"]["pay_period"] | null
          expected_pay_amount?: number | null
          expected_pay_period?: Database["public"]["Enums"]["pay_period"] | null
          max_weekly_hours?: number | null
          min_outreach_pay_amount?: number | null
          min_outreach_pay_period?:
            | Database["public"]["Enums"]["pay_period"]
            | null
          minimum_pay_amount?: number | null
          minimum_pay_period?: Database["public"]["Enums"]["pay_period"] | null
          needs_accommodation?: boolean
          needs_transport?: boolean
          notice_period_days?: number | null
          pay_basis?: Database["public"]["Enums"]["pay_basis"] | null
          pay_currency?: string | null
          person_id: string
          seeking?: boolean
          shift_types?: Database["public"]["Enums"]["shift_type"][]
          updated_at?: string
          willing_to_relocate?: boolean
          willing_to_travel?: boolean
          work_identity_id: string
          work_types?: Database["public"]["Enums"]["work_type"][]
          workplace_types?: Database["public"]["Enums"]["workplace_type"][]
        }
        Update: {
          availability?: Database["public"]["Enums"]["availability_window"]
          available_from?: string | null
          current_pay_amount?: number | null
          current_pay_period?: Database["public"]["Enums"]["pay_period"] | null
          expected_pay_amount?: number | null
          expected_pay_period?: Database["public"]["Enums"]["pay_period"] | null
          max_weekly_hours?: number | null
          min_outreach_pay_amount?: number | null
          min_outreach_pay_period?:
            | Database["public"]["Enums"]["pay_period"]
            | null
          minimum_pay_amount?: number | null
          minimum_pay_period?: Database["public"]["Enums"]["pay_period"] | null
          needs_accommodation?: boolean
          needs_transport?: boolean
          notice_period_days?: number | null
          pay_basis?: Database["public"]["Enums"]["pay_basis"] | null
          pay_currency?: string | null
          person_id?: string
          seeking?: boolean
          shift_types?: Database["public"]["Enums"]["shift_type"][]
          updated_at?: string
          willing_to_relocate?: boolean
          willing_to_travel?: boolean
          work_identity_id?: string
          work_types?: Database["public"]["Enums"]["work_type"][]
          workplace_types?: Database["public"]["Enums"]["workplace_type"][]
        }
        Relationships: [
          {
            foreignKeyName: "person_work_preferences_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "person_work_preferences_work_identity_id_fkey"
            columns: ["work_identity_id"]
            isOneToOne: true
            referencedRelation: "work_identities"
            referencedColumns: ["id"]
          },
        ]
      }
      persons: {
        Row: {
          about: string | null
          avatar_url: string | null
          country_code: string | null
          created_at: string
          date_of_birth: string | null
          deleted_at: string | null
          discoverability: Database["public"]["Enums"]["discoverability"]
          display_name: string | null
          email: string | null
          family_name: string | null
          geo: unknown
          given_name: string | null
          headline: string | null
          highest_education:
            | Database["public"]["Enums"]["education_level"]
            | null
          id: string
          last_active_at: string | null
          locale: string
          location_id: string | null
          location_text: string | null
          onboarding_stage: string
          phone: string | null
          profile_slug: string | null
          timezone: string | null
          updated_at: string
        }
        Insert: {
          about?: string | null
          avatar_url?: string | null
          country_code?: string | null
          created_at?: string
          date_of_birth?: string | null
          deleted_at?: string | null
          discoverability?: Database["public"]["Enums"]["discoverability"]
          display_name?: string | null
          email?: string | null
          family_name?: string | null
          geo?: unknown
          given_name?: string | null
          headline?: string | null
          highest_education?:
            | Database["public"]["Enums"]["education_level"]
            | null
          id: string
          last_active_at?: string | null
          locale?: string
          location_id?: string | null
          location_text?: string | null
          onboarding_stage?: string
          phone?: string | null
          profile_slug?: string | null
          timezone?: string | null
          updated_at?: string
        }
        Update: {
          about?: string | null
          avatar_url?: string | null
          country_code?: string | null
          created_at?: string
          date_of_birth?: string | null
          deleted_at?: string | null
          discoverability?: Database["public"]["Enums"]["discoverability"]
          display_name?: string | null
          email?: string | null
          family_name?: string | null
          geo?: unknown
          given_name?: string | null
          headline?: string | null
          highest_education?:
            | Database["public"]["Enums"]["education_level"]
            | null
          id?: string
          last_active_at?: string | null
          locale?: string
          location_id?: string | null
          location_text?: string | null
          onboarding_stage?: string
          phone?: string | null
          profile_slug?: string | null
          timezone?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "persons_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
        ]
      }
      platform_admins: {
        Row: {
          expires_at: string | null
          granted_at: string
          granted_by: string | null
          is_active: boolean
          person_id: string
          role: string
        }
        Insert: {
          expires_at?: string | null
          granted_at?: string
          granted_by?: string | null
          is_active?: boolean
          person_id: string
          role: string
        }
        Update: {
          expires_at?: string | null
          granted_at?: string
          granted_by?: string | null
          is_active?: boolean
          person_id?: string
          role?: string
        }
        Relationships: [
          {
            foreignKeyName: "platform_admins_granted_by_fkey"
            columns: ["granted_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "platform_admins_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: true
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      profession_aliases: {
        Row: {
          alias: string
          created_at: string
          id: string
          locale: string | null
          occurrences: number
          profession_id: string | null
          status: Database["public"]["Enums"]["taxonomy_status"]
        }
        Insert: {
          alias: string
          created_at?: string
          id?: string
          locale?: string | null
          occurrences?: number
          profession_id?: string | null
          status?: Database["public"]["Enums"]["taxonomy_status"]
        }
        Update: {
          alias?: string
          created_at?: string
          id?: string
          locale?: string | null
          occurrences?: number
          profession_id?: string | null
          status?: Database["public"]["Enums"]["taxonomy_status"]
        }
        Relationships: [
          {
            foreignKeyName: "profession_aliases_profession_id_fkey"
            columns: ["profession_id"]
            isOneToOne: false
            referencedRelation: "professions"
            referencedColumns: ["id"]
          },
        ]
      }
      profession_skills: {
        Row: {
          importance: number
          profession_id: string
          skill_id: string
          source: Database["public"]["Enums"]["source_type"]
        }
        Insert: {
          importance: number
          profession_id: string
          skill_id: string
          source?: Database["public"]["Enums"]["source_type"]
        }
        Update: {
          importance?: number
          profession_id?: string
          skill_id?: string
          source?: Database["public"]["Enums"]["source_type"]
        }
        Relationships: [
          {
            foreignKeyName: "profession_skills_profession_id_fkey"
            columns: ["profession_id"]
            isOneToOne: false
            referencedRelation: "professions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "profession_skills_skill_id_fkey"
            columns: ["skill_id"]
            isOneToOne: false
            referencedRelation: "skills"
            referencedColumns: ["id"]
          },
        ]
      }
      profession_transitions: {
        Row: {
          from_profession_id: string
          last_computed_at: string | null
          median_months: number | null
          median_pay_delta_pct: number | null
          observed_count: number
          prior_strength: number
          to_profession_id: string
        }
        Insert: {
          from_profession_id: string
          last_computed_at?: string | null
          median_months?: number | null
          median_pay_delta_pct?: number | null
          observed_count?: number
          prior_strength?: number
          to_profession_id: string
        }
        Update: {
          from_profession_id?: string
          last_computed_at?: string | null
          median_months?: number | null
          median_pay_delta_pct?: number | null
          observed_count?: number
          prior_strength?: number
          to_profession_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "profession_transitions_from_profession_id_fkey"
            columns: ["from_profession_id"]
            isOneToOne: false
            referencedRelation: "professions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "profession_transitions_to_profession_id_fkey"
            columns: ["to_profession_id"]
            isOneToOne: false
            referencedRelation: "professions"
            referencedColumns: ["id"]
          },
        ]
      }
      professions: {
        Row: {
          category_id: string
          created_at: string
          description: string | null
          embedding: string | null
          external_ids: Json
          id: string
          is_entry_level_friendly: boolean
          merged_into: string | null
          name: string
          requires_license: boolean
          slug: string
          status: Database["public"]["Enums"]["taxonomy_status"]
          typical_education_level:
            | Database["public"]["Enums"]["education_level"]
            | null
          typical_work_types: Database["public"]["Enums"]["work_type"][]
        }
        Insert: {
          category_id: string
          created_at?: string
          description?: string | null
          embedding?: string | null
          external_ids?: Json
          id?: string
          is_entry_level_friendly?: boolean
          merged_into?: string | null
          name: string
          requires_license?: boolean
          slug: string
          status?: Database["public"]["Enums"]["taxonomy_status"]
          typical_education_level?:
            | Database["public"]["Enums"]["education_level"]
            | null
          typical_work_types?: Database["public"]["Enums"]["work_type"][]
        }
        Update: {
          category_id?: string
          created_at?: string
          description?: string | null
          embedding?: string | null
          external_ids?: Json
          id?: string
          is_entry_level_friendly?: boolean
          merged_into?: string | null
          name?: string
          requires_license?: boolean
          slug?: string
          status?: Database["public"]["Enums"]["taxonomy_status"]
          typical_education_level?:
            | Database["public"]["Enums"]["education_level"]
            | null
          typical_work_types?: Database["public"]["Enums"]["work_type"][]
        }
        Relationships: [
          {
            foreignKeyName: "professions_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "job_categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "professions_merged_into_fkey"
            columns: ["merged_into"]
            isOneToOne: false
            referencedRelation: "professions"
            referencedColumns: ["id"]
          },
        ]
      }
      profile_attributes: {
        Row: {
          category_id: string | null
          created_at: string
          data_type: Database["public"]["Enums"]["attribute_data_type"]
          help_text: string | null
          id: string
          is_filterable: boolean
          is_required: boolean
          label: string
          options: Json
          position: number
          profession_id: string | null
          slug: string
          status: Database["public"]["Enums"]["taxonomy_status"]
          unit: string | null
          usable_as_requirement: boolean
        }
        Insert: {
          category_id?: string | null
          created_at?: string
          data_type: Database["public"]["Enums"]["attribute_data_type"]
          help_text?: string | null
          id?: string
          is_filterable?: boolean
          is_required?: boolean
          label: string
          options?: Json
          position?: number
          profession_id?: string | null
          slug: string
          status?: Database["public"]["Enums"]["taxonomy_status"]
          unit?: string | null
          usable_as_requirement?: boolean
        }
        Update: {
          category_id?: string | null
          created_at?: string
          data_type?: Database["public"]["Enums"]["attribute_data_type"]
          help_text?: string | null
          id?: string
          is_filterable?: boolean
          is_required?: boolean
          label?: string
          options?: Json
          position?: number
          profession_id?: string | null
          slug?: string
          status?: Database["public"]["Enums"]["taxonomy_status"]
          unit?: string | null
          usable_as_requirement?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "profile_attributes_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "job_categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "profile_attributes_profession_id_fkey"
            columns: ["profession_id"]
            isOneToOne: false
            referencedRelation: "professions"
            referencedColumns: ["id"]
          },
        ]
      }
      profile_views: {
        Row: {
          context_job_id: string | null
          id: string
          person_id: string
          viewed_at: string
          viewer_company_id: string | null
          viewer_person_id: string | null
          work_identity_id: string | null
        }
        Insert: {
          context_job_id?: string | null
          id?: string
          person_id: string
          viewed_at?: string
          viewer_company_id?: string | null
          viewer_person_id?: string | null
          work_identity_id?: string | null
        }
        Update: {
          context_job_id?: string | null
          id?: string
          person_id?: string
          viewed_at?: string
          viewer_company_id?: string | null
          viewer_person_id?: string | null
          work_identity_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "profile_views_context_job_id_fkey"
            columns: ["context_job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "profile_views_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "profile_views_viewer_company_id_fkey"
            columns: ["viewer_company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "profile_views_viewer_person_id_fkey"
            columns: ["viewer_person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "profile_views_work_identity_id_fkey"
            columns: ["work_identity_id"]
            isOneToOne: false
            referencedRelation: "work_identities"
            referencedColumns: ["id"]
          },
        ]
      }
      project_skills: {
        Row: {
          project_id: string
          skill_id: string
        }
        Insert: {
          project_id: string
          skill_id: string
        }
        Update: {
          project_id?: string
          skill_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "project_skills_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "project_skills_skill_id_fkey"
            columns: ["skill_id"]
            isOneToOne: false
            referencedRelation: "skills"
            referencedColumns: ["id"]
          },
        ]
      }
      projects: {
        Row: {
          created_at: string
          description: string | null
          ended_on: string | null
          id: string
          media: Json
          person_id: string
          role: string | null
          started_on: string | null
          title: string
          url: string | null
          work_identity_id: string | null
        }
        Insert: {
          created_at?: string
          description?: string | null
          ended_on?: string | null
          id?: string
          media?: Json
          person_id: string
          role?: string | null
          started_on?: string | null
          title: string
          url?: string | null
          work_identity_id?: string | null
        }
        Update: {
          created_at?: string
          description?: string | null
          ended_on?: string | null
          id?: string
          media?: Json
          person_id?: string
          role?: string | null
          started_on?: string | null
          title?: string
          url?: string | null
          work_identity_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "projects_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "projects_work_identity_id_fkey"
            columns: ["work_identity_id"]
            isOneToOne: false
            referencedRelation: "work_identities"
            referencedColumns: ["id"]
          },
        ]
      }
      reports: {
        Row: {
          assigned_to: string | null
          created_at: string
          details: string | null
          id: string
          reason: Database["public"]["Enums"]["report_reason"]
          reporter_id: string | null
          resolution: Database["public"]["Enums"]["moderation_action"] | null
          resolution_note: string | null
          resolved_at: string | null
          status: Database["public"]["Enums"]["report_status"]
          subject_id: string
          subject_type: string
        }
        Insert: {
          assigned_to?: string | null
          created_at?: string
          details?: string | null
          id?: string
          reason: Database["public"]["Enums"]["report_reason"]
          reporter_id?: string | null
          resolution?: Database["public"]["Enums"]["moderation_action"] | null
          resolution_note?: string | null
          resolved_at?: string | null
          status?: Database["public"]["Enums"]["report_status"]
          subject_id: string
          subject_type: string
        }
        Update: {
          assigned_to?: string | null
          created_at?: string
          details?: string | null
          id?: string
          reason?: Database["public"]["Enums"]["report_reason"]
          reporter_id?: string | null
          resolution?: Database["public"]["Enums"]["moderation_action"] | null
          resolution_note?: string | null
          resolved_at?: string | null
          status?: Database["public"]["Enums"]["report_status"]
          subject_id?: string
          subject_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "reports_assigned_to_fkey"
            columns: ["assigned_to"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reports_reporter_id_fkey"
            columns: ["reporter_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      saved_jobs: {
        Row: {
          created_at: string
          job_id: string
          person_id: string
        }
        Insert: {
          created_at?: string
          job_id: string
          person_id: string
        }
        Update: {
          created_at?: string
          job_id?: string
          person_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "saved_jobs_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "saved_jobs_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      saved_searches: {
        Row: {
          alert_cadence: string
          created_at: string
          facets: Json
          id: string
          last_alerted_at: string | null
          name: string
          person_id: string
          query_text: string | null
          work_identity_id: string | null
        }
        Insert: {
          alert_cadence?: string
          created_at?: string
          facets?: Json
          id?: string
          last_alerted_at?: string | null
          name: string
          person_id: string
          query_text?: string | null
          work_identity_id?: string | null
        }
        Update: {
          alert_cadence?: string
          created_at?: string
          facets?: Json
          id?: string
          last_alerted_at?: string | null
          name?: string
          person_id?: string
          query_text?: string | null
          work_identity_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "saved_searches_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "saved_searches_work_identity_id_fkey"
            columns: ["work_identity_id"]
            isOneToOne: false
            referencedRelation: "work_identities"
            referencedColumns: ["id"]
          },
        ]
      }
      skill_aliases: {
        Row: {
          alias: string
          created_at: string
          id: string
          locale: string | null
          occurrences: number
          skill_id: string | null
          status: Database["public"]["Enums"]["taxonomy_status"]
        }
        Insert: {
          alias: string
          created_at?: string
          id?: string
          locale?: string | null
          occurrences?: number
          skill_id?: string | null
          status?: Database["public"]["Enums"]["taxonomy_status"]
        }
        Update: {
          alias?: string
          created_at?: string
          id?: string
          locale?: string | null
          occurrences?: number
          skill_id?: string | null
          status?: Database["public"]["Enums"]["taxonomy_status"]
        }
        Relationships: [
          {
            foreignKeyName: "skill_aliases_skill_id_fkey"
            columns: ["skill_id"]
            isOneToOne: false
            referencedRelation: "skills"
            referencedColumns: ["id"]
          },
        ]
      }
      skill_relations: {
        Row: {
          from_skill_id: string
          kind: Database["public"]["Enums"]["relation_kind"]
          source: Database["public"]["Enums"]["source_type"]
          strength: number
          to_skill_id: string
        }
        Insert: {
          from_skill_id: string
          kind: Database["public"]["Enums"]["relation_kind"]
          source?: Database["public"]["Enums"]["source_type"]
          strength?: number
          to_skill_id: string
        }
        Update: {
          from_skill_id?: string
          kind?: Database["public"]["Enums"]["relation_kind"]
          source?: Database["public"]["Enums"]["source_type"]
          strength?: number
          to_skill_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "skill_relations_from_skill_id_fkey"
            columns: ["from_skill_id"]
            isOneToOne: false
            referencedRelation: "skills"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "skill_relations_to_skill_id_fkey"
            columns: ["to_skill_id"]
            isOneToOne: false
            referencedRelation: "skills"
            referencedColumns: ["id"]
          },
        ]
      }
      skills: {
        Row: {
          created_at: string
          description: string | null
          embedding: string | null
          external_ids: Json
          id: string
          merged_into: string | null
          name: string
          slug: string
          status: Database["public"]["Enums"]["taxonomy_status"]
          type: Database["public"]["Enums"]["skill_type"]
        }
        Insert: {
          created_at?: string
          description?: string | null
          embedding?: string | null
          external_ids?: Json
          id?: string
          merged_into?: string | null
          name: string
          slug: string
          status?: Database["public"]["Enums"]["taxonomy_status"]
          type: Database["public"]["Enums"]["skill_type"]
        }
        Update: {
          created_at?: string
          description?: string | null
          embedding?: string | null
          external_ids?: Json
          id?: string
          merged_into?: string | null
          name?: string
          slug?: string
          status?: Database["public"]["Enums"]["taxonomy_status"]
          type?: Database["public"]["Enums"]["skill_type"]
        }
        Relationships: [
          {
            foreignKeyName: "skills_merged_into_fkey"
            columns: ["merged_into"]
            isOneToOne: false
            referencedRelation: "skills"
            referencedColumns: ["id"]
          },
        ]
      }
      support_sessions: {
        Row: {
          admin_id: string
          disclosed_at: string | null
          ended_at: string | null
          expires_at: string
          id: string
          person_id: string
          reason: string
          request_ref: string | null
          started_at: string
        }
        Insert: {
          admin_id: string
          disclosed_at?: string | null
          ended_at?: string | null
          expires_at: string
          id?: string
          person_id: string
          reason: string
          request_ref?: string | null
          started_at?: string
        }
        Update: {
          admin_id?: string
          disclosed_at?: string | null
          ended_at?: string | null
          expires_at?: string
          id?: string
          person_id?: string
          reason?: string
          request_ref?: string | null
          started_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "support_sessions_admin_id_fkey"
            columns: ["admin_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "support_sessions_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      talent_pool_members: {
        Row: {
          added_at: string
          added_by: string | null
          note: string | null
          person_id: string
          pool_id: string
          work_identity_id: string | null
        }
        Insert: {
          added_at?: string
          added_by?: string | null
          note?: string | null
          person_id: string
          pool_id: string
          work_identity_id?: string | null
        }
        Update: {
          added_at?: string
          added_by?: string | null
          note?: string | null
          person_id?: string
          pool_id?: string
          work_identity_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "talent_pool_members_added_by_fkey"
            columns: ["added_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "talent_pool_members_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "talent_pool_members_pool_id_fkey"
            columns: ["pool_id"]
            isOneToOne: false
            referencedRelation: "talent_pools"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "talent_pool_members_work_identity_id_fkey"
            columns: ["work_identity_id"]
            isOneToOne: false
            referencedRelation: "work_identities"
            referencedColumns: ["id"]
          },
        ]
      }
      talent_pools: {
        Row: {
          company_id: string
          created_at: string
          created_by: string | null
          id: string
          name: string
        }
        Insert: {
          company_id: string
          created_at?: string
          created_by?: string | null
          id?: string
          name: string
        }
        Update: {
          company_id?: string
          created_at?: string
          created_by?: string | null
          id?: string
          name?: string
        }
        Relationships: [
          {
            foreignKeyName: "talent_pools_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "talent_pools_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      verifications: {
        Row: {
          claim: Json
          created_at: string
          expires_at: string | null
          id: string
          method: Database["public"]["Enums"]["verification_method"] | null
          person_id: string | null
          provider: string | null
          revoke_reason: string | null
          revoked_at: string | null
          status: Database["public"]["Enums"]["verification_status"]
          subject_id: string
          subject_type: string
          type: Database["public"]["Enums"]["verification_type"]
          verified_at: string | null
          verified_by: string | null
        }
        Insert: {
          claim?: Json
          created_at?: string
          expires_at?: string | null
          id?: string
          method?: Database["public"]["Enums"]["verification_method"] | null
          person_id?: string | null
          provider?: string | null
          revoke_reason?: string | null
          revoked_at?: string | null
          status?: Database["public"]["Enums"]["verification_status"]
          subject_id: string
          subject_type: string
          type: Database["public"]["Enums"]["verification_type"]
          verified_at?: string | null
          verified_by?: string | null
        }
        Update: {
          claim?: Json
          created_at?: string
          expires_at?: string | null
          id?: string
          method?: Database["public"]["Enums"]["verification_method"] | null
          person_id?: string | null
          provider?: string | null
          revoke_reason?: string | null
          revoked_at?: string | null
          status?: Database["public"]["Enums"]["verification_status"]
          subject_id?: string
          subject_type?: string
          type?: Database["public"]["Enums"]["verification_type"]
          verified_at?: string | null
          verified_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "verifications_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      weight_profiles: {
        Row: {
          category_id: string | null
          created_at: string
          id: string
          is_active: boolean
          name: string
          weights: Json
        }
        Insert: {
          category_id?: string | null
          created_at?: string
          id?: string
          is_active?: boolean
          name: string
          weights: Json
        }
        Update: {
          category_id?: string | null
          created_at?: string
          id?: string
          is_active?: boolean
          name?: string
          weights?: Json
        }
        Relationships: [
          {
            foreignKeyName: "weight_profiles_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "job_categories"
            referencedColumns: ["id"]
          },
        ]
      }
      work_authorizations: {
        Row: {
          country_code: string
          created_at: string
          document_id: string | null
          expires_on: string | null
          id: string
          is_verified: boolean
          person_id: string
          requires_sponsorship: boolean | null
          status: Database["public"]["Enums"]["work_auth_status"]
        }
        Insert: {
          country_code: string
          created_at?: string
          document_id?: string | null
          expires_on?: string | null
          id?: string
          is_verified?: boolean
          person_id: string
          requires_sponsorship?: boolean | null
          status: Database["public"]["Enums"]["work_auth_status"]
        }
        Update: {
          country_code?: string
          created_at?: string
          document_id?: string | null
          expires_on?: string | null
          id?: string
          is_verified?: boolean
          person_id?: string
          requires_sponsorship?: boolean | null
          status?: Database["public"]["Enums"]["work_auth_status"]
        }
        Relationships: [
          {
            foreignKeyName: "work_authorizations_document_fk"
            columns: ["document_id"]
            isOneToOne: false
            referencedRelation: "documents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "work_authorizations_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      work_identities: {
        Row: {
          about: string | null
          category_id: string | null
          completeness_score: number
          created_at: string
          discoverability: Database["public"]["Enums"]["discoverability"]
          headline: string | null
          id: string
          identity_embedding: string | null
          is_primary: boolean
          label: string
          person_id: string
          profession_id: string | null
          profession_source: Database["public"]["Enums"]["source_type"]
          status: Database["public"]["Enums"]["work_identity_status"]
          total_experience_months: number | null
          updated_at: string
        }
        Insert: {
          about?: string | null
          category_id?: string | null
          completeness_score?: number
          created_at?: string
          discoverability?: Database["public"]["Enums"]["discoverability"]
          headline?: string | null
          id?: string
          identity_embedding?: string | null
          is_primary?: boolean
          label: string
          person_id: string
          profession_id?: string | null
          profession_source?: Database["public"]["Enums"]["source_type"]
          status?: Database["public"]["Enums"]["work_identity_status"]
          total_experience_months?: number | null
          updated_at?: string
        }
        Update: {
          about?: string | null
          category_id?: string | null
          completeness_score?: number
          created_at?: string
          discoverability?: Database["public"]["Enums"]["discoverability"]
          headline?: string | null
          id?: string
          identity_embedding?: string | null
          is_primary?: boolean
          label?: string
          person_id?: string
          profession_id?: string | null
          profession_source?: Database["public"]["Enums"]["source_type"]
          status?: Database["public"]["Enums"]["work_identity_status"]
          total_experience_months?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "work_identities_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "job_categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "work_identities_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "work_identities_profession_id_fkey"
            columns: ["profession_id"]
            isOneToOne: false
            referencedRelation: "professions"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      omelo_company_slug: { Args: { p_name: string }; Returns: string }
      omelo_mark_application_viewed: {
        Args: { p_application_id: string }
        Returns: undefined
      }
      omelo_nearby_jobs: {
        Args: {
          p_category_id?: string
          p_lat: number
          p_limit?: number
          p_lng: number
          p_min_pay_monthly?: number
          p_no_experience?: boolean
          p_offset?: number
          p_radius_km?: number
          p_search?: string
          p_shift_types?: Database["public"]["Enums"]["shift_type"][]
          p_work_types?: Database["public"]["Enums"]["work_type"][]
        }
        Returns: {
          accepts_no_experience: boolean
          benefits: string[]
          category_slug: string
          company_id: string
          company_name: string
          company_response_hours: number
          company_slug: string
          company_verified: boolean
          distance_km: number
          is_immediate_start: boolean
          job_id: string
          job_pay_period: Database["public"]["Enums"]["pay_period"]
          job_work_type: Database["public"]["Enums"]["work_type"]
          job_workplace: Database["public"]["Enums"]["workplace_type"]
          location_text: string
          min_experience_months: number
          openings: number
          pay_currency: string
          pay_max: number
          pay_min: number
          pay_monthly_min: number
          pay_negotiable: boolean
          profession_name: string
          published_at: string
          quick_apply_enabled: boolean
          shift_types: Database["public"]["Enums"]["shift_type"][]
          title: string
        }[]
      }
      omelo_pay_monthly: {
        Args: {
          p_amount: number
          p_country?: string
          p_period: Database["public"]["Enums"]["pay_period"]
        }
        Returns: number
      }
      omelo_profile_schema_for: {
        Args: { p_work_identity_id?: string }
        Returns: {
          attribute_id: string
          data_type: Database["public"]["Enums"]["attribute_data_type"]
          help_text: string
          is_required: boolean
          label: string
          options: Json
          scope: string
          slug: string
          sort_position: number
        }[]
      }
    }
    Enums: {
      actor_type: "candidate" | "recruiter" | "system" | "admin"
      application_event_type:
        | "created"
        | "viewed"
        | "stage_changed"
        | "shortlisted"
        | "message_sent"
        | "note_added"
        | "document_requested"
        | "document_shared"
        | "interview_scheduled"
        | "interview_completed"
        | "assessment_sent"
        | "assessment_completed"
        | "offer_extended"
        | "offer_responded"
        | "decision_made"
        | "withdrawn"
        | "expired"
      application_state:
        | "applied"
        | "viewed"
        | "shortlisted"
        | "screening"
        | "assessment"
        | "interview"
        | "offer"
        | "hired"
        | "rejected"
        | "withdrawn"
        | "expired"
        | "declined_by_candidate"
      attribute_data_type:
        | "text"
        | "long_text"
        | "number"
        | "boolean"
        | "single_select"
        | "multi_select"
        | "date"
        | "years"
        | "file"
        | "location"
      availability_window:
        | "immediate"
        | "within_7_days"
        | "within_15_days"
        | "within_30_days"
        | "within_60_days"
        | "within_90_days"
        | "flexible"
        | "not_available"
      benefit_type:
        | "accommodation"
        | "transport"
        | "meals"
        | "health_insurance"
        | "life_insurance"
        | "visa_sponsorship"
        | "flight_tickets"
        | "relocation_assistance"
        | "bonus"
        | "overtime_pay"
        | "tips"
        | "commission"
        | "paid_leave"
        | "sick_leave"
        | "parental_leave"
        | "training"
        | "equipment_provided"
        | "uniform_provided"
        | "childcare"
        | "retirement"
        | "stock_options"
        | "gym"
        | "other"
      company_role:
        | "owner"
        | "admin"
        | "recruiter"
        | "hiring_manager"
        | "interviewer"
        | "hr"
        | "finance"
        | "viewer"
      company_size_band:
        | "1-10"
        | "11-50"
        | "51-200"
        | "201-500"
        | "501-1000"
        | "1001-5000"
        | "5001-10000"
        | "10000+"
      discoverability: "private" | "discoverable" | "public"
      document_type:
        | "resume"
        | "cover_letter"
        | "government_id"
        | "passport"
        | "work_permit"
        | "driving_license"
        | "trade_license"
        | "professional_license"
        | "education_certificate"
        | "professional_certificate"
        | "experience_letter"
        | "payslip"
        | "portfolio"
        | "police_clearance"
        | "medical_certificate"
        | "photo"
        | "reference_letter"
        | "other"
      education_level:
        | "none"
        | "primary"
        | "secondary"
        | "high_school"
        | "vocational"
        | "certificate"
        | "diploma"
        | "associate"
        | "bachelor"
        | "master"
        | "doctorate"
        | "professional"
        | "other"
      employment_status: "active" | "on_notice" | "ended" | "terminated"
      evidence_type:
        | "self_declared"
        | "experience"
        | "project"
        | "credential"
        | "license"
        | "assessment"
        | "employer_verified"
        | "reference"
      interview_recommendation: "reject" | "hold" | "advance" | "strong_advance"
      interview_status:
        | "scheduled"
        | "rescheduled"
        | "completed"
        | "cancelled"
        | "no_show_candidate"
        | "no_show_employer"
      interview_type:
        | "phone"
        | "video"
        | "in_person"
        | "group"
        | "walk_in"
        | "trial_shift"
        | "practical_test"
        | "assessment_centre"
        | "panel"
      job_status:
        | "draft"
        | "pending_review"
        | "published"
        | "paused"
        | "expired"
        | "closed"
        | "rejected"
      language_proficiency:
        | "basic"
        | "conversational"
        | "professional"
        | "fluent"
        | "native"
      message_kind: "text" | "action" | "attachment" | "system"
      moderation_action:
        | "none"
        | "warning"
        | "content_removed"
        | "job_unpublished"
        | "account_suspended"
        | "account_banned"
        | "verification_revoked"
      notification_type:
        | "job_match"
        | "job_alert"
        | "saved_search"
        | "application_update"
        | "recruiter_message"
        | "interview_scheduled"
        | "interview_reminder"
        | "offer_received"
        | "document_request"
        | "verification_update"
        | "career_recommendation"
        | "company_update"
        | "job_closing_soon"
        | "profile_reminder"
        | "system"
      offer_status:
        | "draft"
        | "sent"
        | "viewed"
        | "negotiating"
        | "accepted"
        | "declined"
        | "withdrawn"
        | "expired"
      pay_basis: "gross" | "net"
      pay_period:
        | "hour"
        | "day"
        | "week"
        | "fortnight"
        | "month"
        | "year"
        | "per_task"
      proficiency_level:
        | "beginner"
        | "basic"
        | "intermediate"
        | "advanced"
        | "expert"
      relation_kind:
        | "adjacent_to"
        | "prerequisite_of"
        | "substitutable_for"
        | "specialisation_of"
      report_reason:
        | "fraud"
        | "payment_request"
        | "discrimination"
        | "harassment"
        | "misleading_job"
        | "fake_company"
        | "spam"
        | "inappropriate_content"
        | "data_misuse"
        | "other"
      report_status:
        | "open"
        | "triaging"
        | "actioned"
        | "dismissed"
        | "escalated"
      requirement_level: "required" | "preferred" | "nice_to_have"
      shift_type:
        | "day"
        | "evening"
        | "night"
        | "early_morning"
        | "rotating"
        | "split"
        | "flexible"
        | "weekend"
        | "on_call"
      skill_type:
        | "technical"
        | "tool"
        | "equipment"
        | "trade"
        | "physical"
        | "domain"
        | "method"
        | "soft"
        | "language"
        | "safety"
        | "administrative"
      source_type:
        | "user"
        | "import"
        | "inference"
        | "admin"
        | "partner"
        | "employer"
      taxonomy_status: "active" | "pending_review" | "deprecated" | "merged"
      verification_method:
        | "otp"
        | "domain_email"
        | "employer_confirmation"
        | "document_review"
        | "issuer_api"
        | "institution_partner"
        | "government_api"
        | "third_party_provider"
        | "manual_admin"
      verification_status:
        | "unverified"
        | "pending"
        | "verified"
        | "failed"
        | "expired"
        | "revoked"
      verification_type:
        | "identity"
        | "phone"
        | "email"
        | "address"
        | "education"
        | "employment"
        | "license"
        | "certificate"
        | "right_to_work"
        | "background_check"
        | "reference"
      work_auth_status:
        | "citizen"
        | "permanent_resident"
        | "work_permit"
        | "dependent_visa_work_rights"
        | "student_visa_limited"
        | "requires_sponsorship"
        | "no_right_to_work"
      work_identity_status: "active" | "paused" | "archived"
      work_type:
        | "full_time"
        | "part_time"
        | "contract"
        | "freelance"
        | "temporary"
        | "internship"
        | "apprenticeship"
        | "seasonal"
        | "gig"
        | "volunteer"
        | "daily_wage"
      workplace_type:
        | "onsite"
        | "hybrid"
        | "remote"
        | "field_based"
        | "client_site"
        | "multiple_sites"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      actor_type: ["candidate", "recruiter", "system", "admin"],
      application_event_type: [
        "created",
        "viewed",
        "stage_changed",
        "shortlisted",
        "message_sent",
        "note_added",
        "document_requested",
        "document_shared",
        "interview_scheduled",
        "interview_completed",
        "assessment_sent",
        "assessment_completed",
        "offer_extended",
        "offer_responded",
        "decision_made",
        "withdrawn",
        "expired",
      ],
      application_state: [
        "applied",
        "viewed",
        "shortlisted",
        "screening",
        "assessment",
        "interview",
        "offer",
        "hired",
        "rejected",
        "withdrawn",
        "expired",
        "declined_by_candidate",
      ],
      attribute_data_type: [
        "text",
        "long_text",
        "number",
        "boolean",
        "single_select",
        "multi_select",
        "date",
        "years",
        "file",
        "location",
      ],
      availability_window: [
        "immediate",
        "within_7_days",
        "within_15_days",
        "within_30_days",
        "within_60_days",
        "within_90_days",
        "flexible",
        "not_available",
      ],
      benefit_type: [
        "accommodation",
        "transport",
        "meals",
        "health_insurance",
        "life_insurance",
        "visa_sponsorship",
        "flight_tickets",
        "relocation_assistance",
        "bonus",
        "overtime_pay",
        "tips",
        "commission",
        "paid_leave",
        "sick_leave",
        "parental_leave",
        "training",
        "equipment_provided",
        "uniform_provided",
        "childcare",
        "retirement",
        "stock_options",
        "gym",
        "other",
      ],
      company_role: [
        "owner",
        "admin",
        "recruiter",
        "hiring_manager",
        "interviewer",
        "hr",
        "finance",
        "viewer",
      ],
      company_size_band: [
        "1-10",
        "11-50",
        "51-200",
        "201-500",
        "501-1000",
        "1001-5000",
        "5001-10000",
        "10000+",
      ],
      discoverability: ["private", "discoverable", "public"],
      document_type: [
        "resume",
        "cover_letter",
        "government_id",
        "passport",
        "work_permit",
        "driving_license",
        "trade_license",
        "professional_license",
        "education_certificate",
        "professional_certificate",
        "experience_letter",
        "payslip",
        "portfolio",
        "police_clearance",
        "medical_certificate",
        "photo",
        "reference_letter",
        "other",
      ],
      education_level: [
        "none",
        "primary",
        "secondary",
        "high_school",
        "vocational",
        "certificate",
        "diploma",
        "associate",
        "bachelor",
        "master",
        "doctorate",
        "professional",
        "other",
      ],
      employment_status: ["active", "on_notice", "ended", "terminated"],
      evidence_type: [
        "self_declared",
        "experience",
        "project",
        "credential",
        "license",
        "assessment",
        "employer_verified",
        "reference",
      ],
      interview_recommendation: ["reject", "hold", "advance", "strong_advance"],
      interview_status: [
        "scheduled",
        "rescheduled",
        "completed",
        "cancelled",
        "no_show_candidate",
        "no_show_employer",
      ],
      interview_type: [
        "phone",
        "video",
        "in_person",
        "group",
        "walk_in",
        "trial_shift",
        "practical_test",
        "assessment_centre",
        "panel",
      ],
      job_status: [
        "draft",
        "pending_review",
        "published",
        "paused",
        "expired",
        "closed",
        "rejected",
      ],
      language_proficiency: [
        "basic",
        "conversational",
        "professional",
        "fluent",
        "native",
      ],
      message_kind: ["text", "action", "attachment", "system"],
      moderation_action: [
        "none",
        "warning",
        "content_removed",
        "job_unpublished",
        "account_suspended",
        "account_banned",
        "verification_revoked",
      ],
      notification_type: [
        "job_match",
        "job_alert",
        "saved_search",
        "application_update",
        "recruiter_message",
        "interview_scheduled",
        "interview_reminder",
        "offer_received",
        "document_request",
        "verification_update",
        "career_recommendation",
        "company_update",
        "job_closing_soon",
        "profile_reminder",
        "system",
      ],
      offer_status: [
        "draft",
        "sent",
        "viewed",
        "negotiating",
        "accepted",
        "declined",
        "withdrawn",
        "expired",
      ],
      pay_basis: ["gross", "net"],
      pay_period: [
        "hour",
        "day",
        "week",
        "fortnight",
        "month",
        "year",
        "per_task",
      ],
      proficiency_level: [
        "beginner",
        "basic",
        "intermediate",
        "advanced",
        "expert",
      ],
      relation_kind: [
        "adjacent_to",
        "prerequisite_of",
        "substitutable_for",
        "specialisation_of",
      ],
      report_reason: [
        "fraud",
        "payment_request",
        "discrimination",
        "harassment",
        "misleading_job",
        "fake_company",
        "spam",
        "inappropriate_content",
        "data_misuse",
        "other",
      ],
      report_status: ["open", "triaging", "actioned", "dismissed", "escalated"],
      requirement_level: ["required", "preferred", "nice_to_have"],
      shift_type: [
        "day",
        "evening",
        "night",
        "early_morning",
        "rotating",
        "split",
        "flexible",
        "weekend",
        "on_call",
      ],
      skill_type: [
        "technical",
        "tool",
        "equipment",
        "trade",
        "physical",
        "domain",
        "method",
        "soft",
        "language",
        "safety",
        "administrative",
      ],
      source_type: [
        "user",
        "import",
        "inference",
        "admin",
        "partner",
        "employer",
      ],
      taxonomy_status: ["active", "pending_review", "deprecated", "merged"],
      verification_method: [
        "otp",
        "domain_email",
        "employer_confirmation",
        "document_review",
        "issuer_api",
        "institution_partner",
        "government_api",
        "third_party_provider",
        "manual_admin",
      ],
      verification_status: [
        "unverified",
        "pending",
        "verified",
        "failed",
        "expired",
        "revoked",
      ],
      verification_type: [
        "identity",
        "phone",
        "email",
        "address",
        "education",
        "employment",
        "license",
        "certificate",
        "right_to_work",
        "background_check",
        "reference",
      ],
      work_auth_status: [
        "citizen",
        "permanent_resident",
        "work_permit",
        "dependent_visa_work_rights",
        "student_visa_limited",
        "requires_sponsorship",
        "no_right_to_work",
      ],
      work_identity_status: ["active", "paused", "archived"],
      work_type: [
        "full_time",
        "part_time",
        "contract",
        "freelance",
        "temporary",
        "internship",
        "apprenticeship",
        "seasonal",
        "gig",
        "volunteer",
        "daily_wage",
      ],
      workplace_type: [
        "onsite",
        "hybrid",
        "remote",
        "field_based",
        "client_site",
        "multiple_sites",
      ],
    },
  },
} as const
