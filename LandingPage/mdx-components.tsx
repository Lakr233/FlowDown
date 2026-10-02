import Link from "next/link";

type MDXComponents = Record<
  string,
  React.ComponentType<React.HTMLAttributes<HTMLElement>>
>;

export function useMDXComponents(components: MDXComponents): MDXComponents {
  // Styles mirror the landing page palette.
  return {
    h1: ({ children, ...props }) => (
      <h1
        className="font-['Instrument_Serif'] text-4xl text-[#242424] tracking-[-0.5px] mt-8 mb-4 first:mt-0 [&_a]:no-underline"
        {...props}
      >
        {children}
      </h1>
    ),
    h2: ({ children, ...props }) => (
      <h2
        className="text-2xl font-semibold text-[#242424] mt-10 mb-4 pb-2 border-b border-[#e6e6e6] [&_a]:no-underline"
        {...props}
      >
        {children}
      </h2>
    ),
    h3: ({ children, ...props }) => (
      <h3
        className="text-xl font-semibold text-[#242424] mt-8 mb-3 [&_a]:no-underline"
        {...props}
      >
        {children}
      </h3>
    ),
    h4: ({ children, ...props }) => (
      <h4
        className="text-lg font-medium text-[#242424] mt-6 mb-2 [&_a]:no-underline"
        {...props}
      >
        {children}
      </h4>
    ),

    p: ({ children, ...props }) => (
      <p className="text-[#454545] leading-7 mb-4" {...props}>
        {children}
      </p>
    ),

    a: ({ children, ...props }: React.AnchorHTMLAttributes<HTMLAnchorElement>) => {
      const href = props.href;
      const linkClassName = "text-[#242424] font-medium hover:opacity-70 transition-opacity";
      const isExternal = href?.startsWith("http");
      if (isExternal) {
        return (
          <a
            target="_blank"
            rel="noopener noreferrer"
            className={linkClassName}
            {...props}
          >
            {children}
          </a>
        );
      }
      return (
        <Link
          href={href || "#"}
          className={linkClassName}
          {...props}
        >
          {children}
        </Link>
      );
    },

    ul: ({ children, ...props }) => (
      <ul
        className="list-disc list-outside ml-5 mb-4 space-y-2 text-[#454545]"
        {...props}
      >
        {children}
      </ul>
    ),
    ol: ({ children, ...props }) => (
      <ol
        className="list-decimal list-outside ml-5 mb-4 space-y-2 text-[#454545]"
        {...props}
      >
        {children}
      </ol>
    ),
    li: ({ children, ...props }) => (
      <li className="leading-7 pl-1" {...props}>
        {children}
      </li>
    ),

    pre: ({ children, ...props }) => (
      <pre
        className="bg-[#242424] text-[#f6f6f6] rounded-xl p-5 overflow-x-auto mb-6 text-sm font-mono"
        {...props}
      >
        {children}
      </pre>
    ),
    code: ({ children, ...props }) => {
      const isInline = typeof children === "string" && !children.includes("\n");
      if (isInline) {
        return (
          <code
            className="bg-[#ebebeb] text-[#242424] px-1.5 py-0.5 rounded text-sm font-mono"
            {...props}
          >
            {children}
          </code>
        );
      }
      return <code {...props}>{children}</code>;
    },

    blockquote: ({ children, ...props }) => (
      <blockquote
        className="border-l-4 border-[#242424] bg-[#ebebeb] pl-4 pr-4 py-3 my-6 text-[#454545] rounded-r-lg"
        {...props}
      >
        {children}
      </blockquote>
    ),

    table: ({ children, ...props }) => (
      <div className="overflow-x-auto mb-6 rounded-xl border border-[#e6e6e6]">
        <table className="min-w-full" {...props}>
          {children}
        </table>
      </div>
    ),
    thead: ({ children, ...props }) => (
      <thead className="bg-[#ebebeb]" {...props}>
        {children}
      </thead>
    ),
    th: ({ children, ...props }) => (
      <th
        className="border-b border-[#e6e6e6] px-4 py-3 text-left font-semibold text-[#242424] text-sm"
        {...props}
      >
        {children}
      </th>
    ),
    td: ({ children, ...props }) => (
      <td
        className="border-b border-[#e6e6e6] px-4 py-3 text-[#454545] text-sm"
        {...props}
      >
        {children}
      </td>
    ),
    tr: ({ children, ...props }) => (
      <tr className="hover:bg-[#ebebeb]/30 transition-colors" {...props}>
        {children}
      </tr>
    ),
    tbody: ({ children, ...props }) => (
      <tbody className="bg-white" {...props}>
        {children}
      </tbody>
    ),

    hr: (props) => <hr className="my-10 border-[#e6e6e6]" {...props} />,

    img: (props: React.ImgHTMLAttributes<HTMLImageElement>) => {
      const { src, alt } = props;
      if (!src) return null;
      return (
        <span className="block my-6">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={src}
            alt={alt || ""}
            className="rounded-xl max-w-full h-auto shadow-sm border border-[#e6e6e6]"
          />
        </span>
      );
    },

    strong: ({ children, ...props }) => (
      <strong className="font-semibold text-[#242424]" {...props}>
        {children}
      </strong>
    ),

    em: ({ children, ...props }) => (
      <em className="italic" {...props}>
        {children}
      </em>
    ),

    ...components,
  };
}
