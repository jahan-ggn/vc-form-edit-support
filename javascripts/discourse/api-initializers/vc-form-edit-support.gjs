import { service } from "@ember/service";
import Yaml from "js-yaml";
import { apiInitializer } from "discourse/lib/api";
import discourseComputed from "discourse/lib/decorators";

export default apiInitializer((api) => {
  api.modifyClass(
    "service:composer",
    (Class) =>
      class extends Class {
        get hasFormTemplate() {
          return (
            this.formTemplateIds?.length > 0 &&
            !this.get("model.replyingToTopic")
          );
        }
      }
  );

  api.modifyClass(
    "component:form-template-field/wrapper",
    (Class) =>
      class extends Class {
        @service composer;

        _parseMarkdownReply(reply) {
          const lines = reply.split("\n");
          const result = {};
          let currentKey = null;
          let currentValue = [];

          for (let line of lines) {
            const headingMatch = line.match(/^###\s+(.*)/);
            if (headingMatch) {
              if (currentKey) {
                result[this._toKey(currentKey)] = currentValue
                  .join("\n")
                  .trim();
              }
              currentKey = headingMatch[1].trim();
              currentValue = [];
            } else if (currentKey) {
              currentValue.push(line);
            }
          }

          if (currentKey) {
            result[this._toKey(currentKey)] = currentValue.join("\n").trim();
          }

          return result;
        }

        _toKey(label) {
          return label
            .toLowerCase()
            .replace(/[^a-z0-9]+/g, "_")
            .replace(/^_+|_+$/g, "");
        }

        _loadTemplate(templateContent) {
          try {
            this.parsedTemplate = Yaml.load(templateContent);

            this.args.onSelectFormTemplate?.(this.parsedTemplate);

            if (this.composer.model.editingPost) {
              try {
                const parsedValues = this._parseMarkdownReply(
                  this.composer.model.reply
                );
                const initialValues = {};

                (this.parsedTemplate || []).forEach((field) => {
                  const fieldId = field.id;
                  const type = field.type;
                  let value = parsedValues[fieldId];

                  if (value === undefined || value === null) {
                    switch (type) {
                      case "upload":
                      case "multiselect":
                        value = [];
                        break;
                      case "dropdown":
                      case "input":
                      case "textarea":
                      default:
                        value = "";
                    }
                  }

                  if (type === "multiselect" && typeof value === "string") {
                    value = value.split(",").map((v) => v.trim());
                  }

                  if (type === "upload" && typeof value === "string") {
                    const uploads = [];
                    const uploadRegex = /!\[.*?\]\((upload:\/\/.*?)\)/g;
                    let match;
                    while ((match = uploadRegex.exec(value)) !== null) {
                      uploads.push(match[1]);
                    }
                    value = uploads;
                  }

                  initialValues[fieldId] = value;
                });

                this.initialValues = initialValues;
              } catch {
                this.initialValues = {};
              }
            }
          } catch (e) {
            this.error = e;
          }
        }
      }
  );

  api.modifyClass(
    "component:composer-editor",
    (Class) =>
      class extends Class {
        @discourseComputed(
          "composer.formTemplateIds",
          "composer.model.replyingToTopic"
        )
        showFormTemplateForm(formTemplateIds, replyingToTopic) {
          return formTemplateIds?.length > 0 && !replyingToTopic;
        }
      }
  );
});
