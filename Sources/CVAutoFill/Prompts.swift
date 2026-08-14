import Foundation

// Ported from cv_autofill_extension/background.js — keep these in sync if the
// extension's prompts change, since the two apps intentionally behave the same way.
enum Prompts {
    static let cvSchema = """
    Extract the candidate's information from the attached CV/resume into a JSON object with exactly this shape:
    {
      "full_name": "",
      "email": "",
      "phone": "",
      "location": "",
      "linkedin": "",
      "github": "",
      "portfolio": "",
      "summary": "",
      "work_experience": [{"title": "", "company": "", "start": "", "end": "", "description": ""}],
      "education": [{"degree": "", "institution": "", "start": "", "end": ""}],
      "skills": []
    }
    Only include information actually present in the CV. Use "" for missing string fields and [] for missing arrays.
    Do not invent employers, dates, or credentials that aren't in the document.
    Respond with JSON only — no markdown code fences, no commentary, no text before or after the JSON object.
    """

    static let coverLetterWrite = """
    You are helping a job applicant write a new cover letter tailored to a specific job posting.
    You are given:
    - CV_DATA: the applicant's CV, as structured JSON.
    - REFERENCE_COVER_LETTER: a cover letter the applicant has written before. Use it only as a guide for their voice, tone, and typical structure — do not copy it verbatim, and do not reuse specifics (company names, roles) from it. Write a new letter tailored to JOB_CONTEXT.
    - JOB_CONTEXT: text the applicant pasted from a job posting. It may be incomplete, noisy, or missing.

    Write a new cover letter grounded only in facts from CV_DATA — never invent employers, dates, skills, or achievements that aren't in CV_DATA. Keep it concise (250-400 words), professional, and specific to the role in JOB_CONTEXT where the context allows it. If JOB_CONTEXT is missing or unhelpful, write a solid general-purpose letter from CV_DATA instead of inventing job details.

    Respond as JSON: {"cover_letter": "..."}. Respond with JSON only — no markdown code fences, no commentary.
    """

    static let cvTailor = """
    You are helping a job applicant tailor their CV/resume for a specific job posting.
    You are given CV_DATA (structured JSON), JOB_CONTEXT (text the applicant pasted from a job posting — may be incomplete or missing), ABOUT_ME (free-form notes from the applicant), and ADDITIONAL_RESOURCES (extra context from the applicant's own websites/notes).

    Produce a tailored version of the CV as JSON with exactly this shape:
    {
      "full_name": "",
      "email": "",
      "phone": "",
      "location": "",
      "linkedin": "",
      "github": "",
      "portfolio": "",
      "summary": "",
      "work_experience": [{"title": "", "company": "", "start": "", "end": "", "bullets": ["", "..."]}],
      "education": [{"degree": "", "institution": "", "start": "", "end": ""}],
      "skills": []
    }

    Rules:
    - Never invent employers, dates, titles, or achievements that aren't in CV_DATA, ABOUT_ME, or ADDITIONAL_RESOURCES. This is a rewrite/re-emphasis of real facts, not fiction.
    - You may reorder or trim skills, and rewrite the summary to speak directly to the role in JOB_CONTEXT.
    - Convert each role's experience into 2-4 concise, achievement-oriented "bullets" (rewrite any prose-style description into bullet points).
    - If JOB_CONTEXT is missing or unhelpful, produce a solid general-purpose tailored CV instead of inventing job specifics.

    Respond with JSON only — no markdown code fences, no commentary.
    """

    static let ask = """
    You are helping a job applicant who is filling out a job application and got stuck on a question.
    You are given CV_DATA, ABOUT_ME, ADDITIONAL_RESOURCES, and the applicant's QUESTION.

    Answer the question directly and concisely, grounded only in the given information. If you don't have enough information to answer factually, say so plainly rather than guessing or inventing facts — the applicant will fill in the real answer themselves.

    Respond as JSON: {"answer": "..."}. Respond with JSON only — no markdown code fences, no commentary.
    """
}

enum ContextBuilder {
    static func build(aboutMe: String, resources: [ResourceItem]) -> String {
        var parts = ["ABOUT_ME:\n\(aboutMe.isEmpty ? "(none provided)" : aboutMe)"]
        if resources.isEmpty {
            parts.append("ADDITIONAL_RESOURCES:\n(none provided)")
        } else {
            let recent = resources.suffix(8)
            let items = recent.map { r -> String in
                let header = r.url != nil ? "\(r.label) (\(r.url!))" : r.label
                let content = String(r.content.prefix(1500))
                return "- \(header):\n\(content)"
            }
            parts.append("ADDITIONAL_RESOURCES:\n\(items.joined(separator: "\n\n"))")
        }
        return parts.joined(separator: "\n\n")
    }
}
